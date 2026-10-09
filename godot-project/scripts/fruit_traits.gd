extends RefCounted
## Corpse-fruit module — foe-fruit ("one fruit, two doors") door only.
##
## Bot 003 (Wrath), Gameplay Engineer A. Implements FRUIT-SPEC REV 4.1
## (BOT-004 Styx; Tucker rulings R1–R6, 2026-10-08; F1/F2/F3 + Q1/Q4, 2026-10-09)
## + FRUIT-OBJECT-MODEL REV 2
## foe-fruit door (§1.1 corpse-plant record, §1.2 carried record, §3
## eaten[]/active_traits[]/tokens[], §3.3 permanent-until-evicted slots,
## §3.5 tokens FIFO 5, §6 rot lifecycle).
##
## SCOPE: foe-fruit door ONLY. The spore-fruit door belongs to the breeding
## lane and is not touched here.
##
## Design decisions (wiring — flagged, not hidden):
##   - Static library, no class_name, no autoload — consumers preload this
##     script, so it works under headless -s test scripts (autoloads don't
##     load there). Same pattern as feeding_loop.gd / breeding.gd.
##   - State-dictionary based (plain JSONC-safe dicts), lazy shape creation,
##     so old saves pick the fruit shapes up on load. `gs` is the GameState
##     node (or any object exposing a `.state` Dictionary).
##   - Step anchor is state["run"]["steps_total"] (StepDriver basis). All
##     entry points take `steps_total` explicitly; `get_steps()` reads the
##     anchor with a 0 fallback.
##   - Potency is TIER-RELATIVE (primary, per the task directive):
##     base (story-side trait row) x tier_mult (1.0/1.5/2.0) x dilution
##     (potency_mult 1.0/0.5/0.25 floor). Results carry basis "tier_relative";
##     absolute Might/Guard calibration is a downstream derivation-lane job
##     against the locked stat block (STAT-BLOCK-VALIDATION.md).
##   - Trait rows are story-side (data/traits.json, keyed under "traits").
##     A table may be passed in directly for testability; the JSON read is
##     a cached fallback. The module never invents trait rows.
##
## No class_name / autoload on purpose (see above).
##   const FruitTraits = preload("res://scripts/fruit_traits.gd")

const TRAITS_PATH := "res://data/traits.json"

## Locked: rot timer length in steps (R3). Derived, never stored:
##   steps_remaining = ROT_STEPS - (steps_total - emerged_at_step)
const ROT_STEPS := 1200

## Foe manifestation tiers (creature-data vocabulary; NOT the player's Form
## tiers). Tier floor for fruiting: Skeletal Body and above.
const TIER_SKELETAL := "Skeletal Body"
const TIER_FALSE_FLESH := "False Flesh"
const TIER_FULL_MANIFEST := "Full Manifestation"
## "Human Body" is a display alias of False Flesh (canon FRUIT-SPEC §5.5).
const TIER_ALIAS_HUMAN := "Human Body"

const TIER_MULTS := {
	TIER_SKELETAL: 1.0,
	TIER_FALSE_FLESH: 1.5,
	TIER_FULL_MANIFEST: 2.0,
}
## Canon rank order, weakest first (tiebreak / floor comparisons).
const TIER_RANK := [TIER_SKELETAL, TIER_FALSE_FLESH, TIER_FULL_MANIFEST]

const LEAN_NECRO := "necro"
const LEAN_ETERNI := "eterni"

## R4 locks.
const TRAIT_SLOT_CAP := 3
const TOKEN_CAP := 5

## §3.3 dilution: halved per repeat, floor 1/4.
const DILUTION_STEP := 0.5
const DILUTION_FLOOR := 0.25

## §1.4 locked exclusions (R5). No fruit, no exceptions without a canon change.
## ENC-keyed rows (scripted / non-corpse patterns) and foe-keyed rows
## (named foes excluded regardless of encounter).
const LOCKED_EXCLUSION_ENCS := [
	"ENC-002",  ## tentacle: no on-screen slaying
	"ENC-003",  ## Wrath rival fight: spares, not kills
	"ENC-004",  ## scripted losses: Mollosar falls
	"ENC-006",  ## willing-reap pattern: guided, not slain (was ENC-005, R12 crosswalk)
	"ENC-020",  ## Ivy arena: absorbed, not killed (was ENC-013, R12 crosswalk)
	"ENC-019",  ## Malice: dispersal, not a corpse (was ENC-018, R12 crosswalk)
	"ENC-021",  ## Wrath gate fight: spares, not kills (Wrath joins Mollosar)
]
const LOCKED_EXCLUSION_FOES := [
	"bellmaw",  ## puzzle boss: no corpse
	"kanryu",   ## sealed bounty: no fruit
	"wrath",    ## the gate fight: spares, not kills (Wrath joins Mollosar)
]

static var _traits_cache: Dictionary = {}


static func _load_traits() -> Dictionary:
	if not _traits_cache.is_empty():
		return _traits_cache
	if not FileAccess.file_exists(TRAITS_PATH):
		return {}
	var f := FileAccess.open(TRAITS_PATH, FileAccess.READ)
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		_traits_cache = parsed
	return _traits_cache


## Story-side trait row lookup. `table` overrides the JSON file (tests pass
## their own table). Rows carry the Might/Guard BASE deltas the tier
## multiplier scales. Returns {} when the trait is unknown.
static func trait_row(trait_id: String, table: Dictionary = {}) -> Dictionary:
	var t: Dictionary = table
	if t.is_empty():
		t = _load_traits().get("traits", {})
	var row = t.get(trait_id, {})
	return row if row is Dictionary else {}


## Normalize display aliases to the canonical tier vocabulary.
static func canon_tier(tier: String) -> String:
	if tier == TIER_ALIAS_HUMAN:
		return TIER_FALSE_FLESH
	return tier


## Tier-relative potency multiplier (×1.0/×1.5/×2.0, canon FRUIT-SPEC §2.2).
## Unknown tiers refuse (return 0.0) rather than guess.
static func tier_mult(tier: String) -> float:
	return float(TIER_MULTS.get(canon_tier(tier), 0.0))


## True iff `tier` is at least the floor in canon rank order.
static func tier_at_least(tier: String, floor: String) -> bool:
	var t := canon_tier(tier)
	var fl := canon_tier(floor)
	if not TIER_RANK.has(t) or not TIER_RANK.has(fl):
		return false
	return TIER_RANK.find(t) >= TIER_RANK.find(fl)


## True iff the encounter/foe is in the §1.4 locked exclusion set (R5).
static func is_excluded(enc_ref: String, foe_id: String) -> bool:
	if LOCKED_EXCLUSION_ENCS.has(enc_ref):
		return true
	return LOCKED_EXCLUSION_FOES.has(String(foe_id).to_lower())


## The step anchor: state["run"]["steps_total"] (StepDriver basis). 0 when
## the run section is absent (mid-run repair belongs to the driver).
static func get_steps(gs) -> int:
	var run = (gs.state as Dictionary).get("run", {})
	if not (run is Dictionary):
		return 0
	return int((run as Dictionary).get("steps_total", 0))


## Lazily build the state shapes. Returns nothing; reads are defensive
## everywhere below so a partially-present shape still works.
static func _plants(gs) -> Dictionary:
	var s: Dictionary = gs.state
	if not s.has("plants") or not (s["plants"] is Dictionary):
		s["plants"] = {"corpse_fruit": [], "corpse_seq": 0}
	var p: Dictionary = s["plants"]
	if not (p.get("corpse_fruit") is Array):
		p["corpse_fruit"] = []
	if not (p.get("corpse_seq") is int):
		p["corpse_seq"] = 0
	return p


static func _player_fruit(gs) -> Dictionary:
	var s: Dictionary = gs.state
	if not s.has("player") or not (s["player"] is Dictionary):
		s["player"] = {}
	var pl: Dictionary = s["player"]
	if not pl.has("fruit") or not (pl["fruit"] is Dictionary):
		pl["fruit"] = {
			"carried": [], "eaten": [], "active_traits": [],
			"trait_seq": 0, "tokens": [],
		}
	var fr: Dictionary = pl["fruit"]
	for key in ["carried", "eaten", "active_traits", "tokens"]:
		if not (fr.get(key) is Array):
			fr[key] = []
	if not (fr.get("trait_seq") is int):
		fr["trait_seq"] = 0
	return fr


static func _ledger_fruit(gs) -> Dictionary:
	var s: Dictionary = gs.state
	if not s.has("ledger") or not (s["ledger"] is Dictionary):
		s["ledger"] = {}
	var led: Dictionary = s["ledger"]
	if not led.has("fruit") or not (led["fruit"] is Dictionary):
		led["fruit"] = {"harvested": [], "necro_count": 0, "eterni_count": 0}
	var fr: Dictionary = led["fruit"]
	if not (fr.get("harvested") is Array):
		fr["harvested"] = []
	for key in ["necro_count", "eterni_count"]:
		if not (fr.get(key) is int):
			fr[key] = 0
	return fr


## §1.1 eligibility conjunction (R1 hard regret gate).
## foe = {foe_id, enc_ref, tier, fruit_eligibility (story-side regret tag,
##        tri-state: eligible|ineligible|pending), corpse_produced, mortal_world}
## Returns {ok: bool, reason: String}. reason is "eligible" on success.
static func check_eligibility(foe: Dictionary) -> Dictionary:
	var foe_id := str(foe.get("foe_id", ""))
	var enc_ref := str(foe.get("enc_ref", ""))
	var tier := canon_tier(str(foe.get("tier", "")))
	if foe_id == "":
		return {"ok": false, "reason": "missing_foe_id"}
	if is_excluded(enc_ref, foe_id):
		return {"ok": false, "reason": "locked_exclusion"}
	if bool(foe.get("mortal_world", false)):
		return {"ok": false, "reason": "mortal_world"}  ## INV-5 / R15
	if not tier_at_least(tier, TIER_SKELETAL):
		return {"ok": false, "reason": "tier_below_floor"}
	if not bool(foe.get("corpse_produced", false)):
		return {"ok": false, "reason": "no_corpse"}
	if str(foe.get("fruit_eligibility", "")).strip_edges() != "eligible":
		return {"ok": false, "reason": "no_regret_tag"}
	return {"ok": true, "reason": "eligible"}


## Q1 (SANCTIONED authoring-fallback): the primary lean path is the
## caller-passed lean from the story-side signature field; this helper
## applies when the story lane hasn't authored one. Dominant signature
## wins; true ties resolve Necro (R2 — deterministic, no randomness).
static func determine_lean(death_weight: float, light_weight: float) -> String:
	if light_weight > death_weight:
		return LEAN_ETERNI
	return LEAN_NECRO


## Luna's lean tell: the fruit's lean is revealed, power stays hidden.
static func luna_lean(rec: Dictionary) -> String:
	return str(rec.get("lean", ""))


## UI-safe description: source foe, tier, and lean are known; the trait is
## hidden until eaten (power hidden until eaten, canon).
static func describe(rec: Dictionary) -> Dictionary:
	return {
		"fruit_id": str(rec.get("fruit_id", "")),
		"source_foe": str(rec.get("source_foe", "")),
		"tier": str(rec.get("tier", "")),
		"lean": str(rec.get("lean", "")),
		"trait": "unknown",
	}


## Rot math (R3, §6): steps_remaining = ROT_STEPS - (steps_total -
## emerged_at_step). DERIVED, never stored. Rot iff <= 0.
static func steps_remaining(emerged_at_step: int, steps_total: int) -> int:
	return ROT_STEPS - (steps_total - emerged_at_step)


static func is_rotted(emerged_at_step: int, steps_total: int) -> bool:
	return steps_remaining(emerged_at_step, steps_total) <= 0


## §1.3 plant emergence (presentation: corpse -> soil darkens -> plant rises
## in ~8-10s; here the record flips from "growing" when finished via
## finish_growth()). One foe -> one plant -> one fruit: a second emergence
## for the same foe_id is refused (no farming the same corpse).
## lean resolution happens at emergence: caller passes the story-side lean;
## when the story lane hasn't authored one, the caller passes
## determine_lean(death_weight, light_weight) output instead (Q1).
## Q4: emerged_at_step is NOT stamped here — only at finish_growth().
static func emerge_plant(gs, foe: Dictionary, room_id: String, lean: String,
		trait_id: String, steps_total: int = -1) -> Dictionary:
	var elig := check_eligibility(foe)
	if not bool(elig.get("ok", false)):
		return {"ok": false, "reason": str(elig.get("reason", ""))}
	if lean != LEAN_NECRO and lean != LEAN_ETERNI:
		return {"ok": false, "reason": "bad_lean"}
	if trait_id == "":
		return {"ok": false, "reason": "missing_trait_id"}
	var p := _plants(gs)
	var foe_id := str(foe.get("foe_id", ""))
	for existing in (p["corpse_fruit"] as Array):
		if str((existing as Dictionary).get("foe_id", "")) == foe_id:
			return {"ok": false, "reason": "already_fruited"}
	if steps_total < 0:
		steps_total = get_steps(gs)
	var seq := int(p.get("corpse_seq", 0)) + 1
	p["corpse_seq"] = seq
	var plant_id := "corpseplant_%d" % seq
	var tier := canon_tier(str(foe.get("tier", "")))
	var plant := {
		"plant_id": plant_id,
		"room_id": room_id,
		"foe_id": foe_id,
		"enc_ref": str(foe.get("enc_ref", "")),  ## provenance only — NOT the gate
		"lean": lean,
		"trait_id": trait_id,
		"tier": tier,
		"planted_at_step": steps_total,
		"status": "growing",
		"fruit": {},
	}
	(p["corpse_fruit"] as Array).append(plant)
	return {"ok": true, "plant": plant}


## Plant lookup by id. Returns {} when absent.
static func _find_plant(p: Dictionary, plant_id: String) -> Dictionary:
	for plant_v in (p.get("corpse_fruit", []) as Array):
		var plant: Dictionary = plant_v
		if str(plant.get("plant_id", "")) == plant_id:
			return plant
	return {}


## ledger.fruit.harvested[] row writer (§5.4): {fruit_id, source_foe,
## outcome (eaten|rotted), steps}.
static func _log_harvested(gs, fruit_id: String, source_foe: String,
		outcome: String, steps: int) -> void:
	var led := _ledger_fruit(gs)
	(led["harvested"] as Array).append({
		"fruit_id": fruit_id, "source_foe": source_foe,
		"outcome": outcome, "steps": steps,
	})


## In-place outcome update for a harvested[] row (rows open at
## finish_growth with outcome "harvestable", then resolve to eaten|rotted).
static func _set_harvest_outcome(gs, fruit_id: String, outcome: String,
		steps: int) -> void:
	for row_v in (_ledger_fruit(gs)["harvested"] as Array):
		var row: Dictionary = row_v
		if str(row.get("fruit_id", "")) == fruit_id:
			row["outcome"] = outcome
			row["steps"] = steps
			return
	_log_harvested(gs, fruit_id, "", outcome, steps)  ## defensive: row missing


## §1.3 growth completion (presentation: the ~8-10s rise; here the record
## flips from "growing"). Writes the fruit sub-record and stamps
## emerged_at_step — Q4: ONLY here. No interim value during growing. The
## 1,200-step rot timer (R3) starts at this stamp, never earlier.
## Double-finish is idempotent (never restamps the anchor).
static func finish_growth(gs, plant_id: String, steps_total: int = -1) -> Dictionary:
	var p := _plants(gs)
	var plant := _find_plant(p, plant_id)
	if plant.is_empty():
		return {"ok": false, "reason": "missing_plant"}
	if str(plant.get("status", "")) == "harvestable":
		return {"ok": true, "plant": plant}  ## idempotent: keep the anchor
	if str(plant.get("status", "")) != "growing":
		return {"ok": false, "reason": "not_growing"}
	if steps_total < 0:
		steps_total = get_steps(gs)
	plant["emerged_at_step"] = steps_total
	plant["fruit"] = {
		"fruit_id": "fruit_" + plant_id,
		"source_foe": str(plant.get("foe_id", "")),
		"tier": str(plant.get("tier", "")),
		"lean": str(plant.get("lean", "")),
		"trait_id": str(plant.get("trait_id", "")),
		"emerged_at_step": steps_total,
	}
	plant["status"] = "harvestable"
	var fruit: Dictionary = plant["fruit"]
	_log_harvested(gs, str(fruit.get("fruit_id", "")),
		str(plant.get("foe_id", "")), "harvestable", steps_total)
	return {"ok": true, "plant": plant}


## Harvest is a pickup: the fruit leaves the plant and becomes a carried
## record. The carried record is self-sufficient (INV-4): the rot anchor is
## carried over, never reset — harvest never restarts the 1,200-step clock.
## The plant becomes a husk ("harvested"); the gravebloom persists separately.
static func harvest_fruit(gs, plant_id: String, steps_total: int = -1) -> Dictionary:
	var p := _plants(gs)
	var plant := _find_plant(p, plant_id)
	if plant.is_empty():
		return {"ok": false, "reason": "missing_plant"}
	if str(plant.get("status", "")) != "harvestable":
		return {"ok": false, "reason": "not_harvestable"}
	if steps_total < 0:
		steps_total = get_steps(gs)
	var fr: Dictionary = plant.get("fruit", {})
	var anchor := int(fr.get("emerged_at_step", steps_total))
	if is_rotted(anchor, steps_total):
		return {"ok": false, "reason": "rotted"}
	var carried := {
		"plant_id": plant_id,
		"fruit_id": str(fr.get("fruit_id", "fruit_" + plant_id)),
		"origin": "foe-fruit",
		"source_foe": str(plant.get("foe_id", "")),
		"tier": str(plant.get("tier", "")),
		"lean": str(plant.get("lean", "")),
		"trait_id": str(plant.get("trait_id", "")),
		"emerged_at_step": anchor,
		"harvested_at_step": steps_total,
	}
	var pf := _player_fruit(gs)
	(pf["carried"] as Array).append(carried)
	plant["status"] = "harvested"  ## husk remains; the gravebloom persists separately
	return {"ok": true, "carried": carried, "plant": plant}


## Step sweep — StepDriver fan-out target (feeding -> plant-timers -> R22).
## `delta` is the number of steps the driver advanced. The run clock
## (state["run"]["steps_total"]) moves forward, then every live fruit —
## on-plant and carried — is swept against its emerged_at_step anchor.
## Returns {ok: bool, rotted: [fruit_id, ...]}. Rots resolve their
## harvested[] rows to "rotted" (§5.4). R3: the timer runs everywhere —
## there is no banking fruit on plants or in pockets.
static func on_steps_taken(gs, delta: int) -> Dictionary:
	var s: Dictionary = gs.state
	if not s.has("run") or not (s["run"] is Dictionary):
		s["run"] = {}
	var run: Dictionary = s["run"]
	(run as Dictionary)["steps_total"] = int((run as Dictionary).get("steps_total", 0)) + delta
	var steps_total := int((run as Dictionary).get("steps_total", 0))
	var rotted: Array = []
	## On-plant fruit.
	var p := _plants(gs)
	for plant_v in (p["corpse_fruit"] as Array):
		var plant: Dictionary = plant_v
		if str(plant.get("status", "")) != "harvestable":
			continue
		var fr: Dictionary = plant.get("fruit", {})
		if fr.is_empty():
			continue
		var anchor := int(fr.get("emerged_at_step", -1))
		if anchor < 0:
			continue
		if is_rotted(anchor, steps_total):
			plant["status"] = "rotted"
			rotted.append(str(fr.get("fruit_id", "")))
			_set_harvest_outcome(gs, str(fr.get("fruit_id", "")),
				"rotted", steps_total)
	## Carried fruit shares the same clock.
	var pf := _player_fruit(gs)
	var kept: Array = []
	for c_v in (pf["carried"] as Array):
		var c: Dictionary = c_v
		if is_rotted(int(c.get("emerged_at_step", 0)), steps_total):
			rotted.append(str(c.get("fruit_id", "")))
			_set_harvest_outcome(gs, str(c.get("fruit_id", "")),
				"rotted", steps_total)
		else:
			kept.append(c)
	pf["carried"] = kept
	return {"ok": true, "rotted": rotted}


## Eat a carried fruit: grants the foe's signature trait (design logic, not
## raw stats — §0.1.8). One trait per fruit; no same-trait stacking: a repeat
## of an already-active trait dilutes (§2.3 — x1/2, floor x1/4) and consumes
## no slot. Fresh grants fill the 3 trait slots (R4); a 4th grant evicts the
## oldest (R19) — eating is NEVER blocked. eaten[] is append-only history.
## Potency is tier-relative (basis "tier_relative"); absolute Might/Guard
## calibration is a downstream derivation-lane job against the locked
## stat block (R6).
static func consume(gs, fruit_id: String, steps_total: int = -1,
		table: Dictionary = {}) -> Dictionary:
	var pf := _player_fruit(gs)
	var carried: Dictionary = {}
	var idx := -1
	var arr: Array = pf["carried"]
	for i in range(arr.size()):
		var c: Dictionary = arr[i]
		if str(c.get("fruit_id", "")) == fruit_id:
			carried = c
			idx = i
			break
	if idx < 0:
		return {"ok": false, "reason": "missing"}
	if steps_total < 0:
		steps_total = get_steps(gs)
	if is_rotted(int(carried.get("emerged_at_step", 0)), steps_total):
		return {"ok": false, "reason": "rotted"}
	var trait_id := str(carried.get("trait_id", ""))
	var tier := str(carried.get("tier", ""))
	var lean := str(carried.get("lean", ""))
	var active: Array = pf["active_traits"]
	var potency := 1.0
	var diluted := false
	var evicted := ""
	var active_idx := -1
	for i in range(active.size()):
		if str((active[i] as Dictionary).get("trait_id", "")) == trait_id:
			active_idx = i
			break
	if active_idx >= 0:
		## Repeat of an active trait: dilution only, no slot consumed.
		potency = maxf(DILUTION_FLOOR,
			float((active[active_idx] as Dictionary).get("potency_mult", 1.0)) * DILUTION_STEP)
		(active[active_idx] as Dictionary)["potency_mult"] = potency
		diluted = true
	else:
		## Fresh grant: evict the oldest when the 3 slots are full.
		if active.size() >= TRAIT_SLOT_CAP:
			evicted = str((active[0] as Dictionary).get("trait_id", ""))
			active.remove_at(0)
	var applied := potency_applied(trait_id, tier, potency, table)
	if diluted:
		(active[active_idx] as Dictionary)["might"] = float(applied.get("might", 0.0))
		(active[active_idx] as Dictionary)["guard"] = float(applied.get("guard", 0.0))
	else:
		active.append({
			"trait_id": trait_id,
			"potency_mult": potency,
			"might": float(applied.get("might", 0.0)),
			"guard": float(applied.get("guard", 0.0)),
			"basis": "tier_relative",
			"lean": lean,
			"source_foe": str(carried.get("source_foe", "")),
			"fruit_id": fruit_id,
			"fruit_granted": true,
			"mode": "permanent",
		})
	(pf["eaten"] as Array).append({
		"fruit_id": fruit_id,
		"source_foe": str(carried.get("source_foe", "")),
		"tier": tier,
		"lean": lean,
		"trait_id": trait_id,
		"potency_mult": potency,
		"emerged_at_step": int(carried.get("emerged_at_step", 0)),
		"steps_emerged_at": int(carried.get("emerged_at_step", 0)),
		"steps_eaten_at": steps_total,
	})
	arr.remove_at(idx)
	## One visual token per consumed fruit, max 5, FIFO (R4).
	var tokens: Array = pf["tokens"]
	tokens.append({"trait_id": trait_id, "lean": lean,
		"sprite_anchor": "mark_" + trait_id})
	while tokens.size() > TOKEN_CAP:
		tokens.pop_front()
	## Corruption / seizure inputs (§6.4): opposed lean tallies.
	var led := _ledger_fruit(gs)
	if lean == LEAN_ETERNI:
		led["eterni_count"] = int(led.get("eterni_count", 0)) + 1
	else:
		led["necro_count"] = int(led.get("necro_count", 0)) + 1
	_set_harvest_outcome(gs, fruit_id, "eaten", steps_total)
	return {
		"ok": true, "fruit_id": fruit_id, "trait_id": trait_id,
		"potency_mult": potency, "might": float(applied.get("might", 0.0)),
		"guard": float(applied.get("guard", 0.0)), "basis": "tier_relative",
		"diluted": diluted, "evicted": evicted,
	}


## Gravebloom marker (canon: every defeat grows a persistent gravebloom).
## Visual room-state only — the ONLY writer of ledger.graveblooms[]
## (INV-7 / R18: lifecycle paths never write gravebloom-family keys).
static func record_gravebloom(gs, room_id: String, foe_ref: String,
		fruit_spawned: bool) -> Dictionary:
	var s: Dictionary = gs.state
	if not s.has("ledger") or not (s["ledger"] is Dictionary):
		s["ledger"] = {}
	var led: Dictionary = s["ledger"]
	if not led.has("graveblooms") or not (led["graveblooms"] is Array):
		led["graveblooms"] = []
	var gbs: Array = led["graveblooms"]
	(gbs as Array).append({
		"room_id": room_id, "foe_ref": foe_ref, "fruit_spawned": fruit_spawned,
	})
	return {"ok": true}


## Tier-relative potency derivation (§2.2, R6): base (story-side trait row)
## x tier_mult (1.0/1.5/2.0) x potency_mult (dilution 1.0/0.5/0.25 floor).
## Pure: no state touched. Results carry basis "tier_relative"; absolute
## Might/Guard calibration is a downstream derivation-lane job.
static func potency_applied(trait_id: String, tier: String,
		potency_mult: float, table: Dictionary = {}) -> Dictionary:
	var row := trait_row(trait_id, table)
	var tm := tier_mult(tier)
	return {
		"might": float(row.get("might", 0)) * tm * potency_mult,
		"guard": float(row.get("guard", 0)) * tm * potency_mult,
		"basis": "tier_relative",
	}


## Read accessors for consumers / tests.
static func carried(gs) -> Array:
	return _player_fruit(gs).get("carried", [])


static func active_traits(gs) -> Array:
	return _player_fruit(gs).get("active_traits", [])


static func tokens(gs) -> Array:
	return _player_fruit(gs).get("tokens", [])


static func ledger(gs) -> Dictionary:
	return _ledger_fruit(gs)
