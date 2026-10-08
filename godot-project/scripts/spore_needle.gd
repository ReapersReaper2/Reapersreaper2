extends RefCounted
## Spore Needle system (wiring).
##
## LOCKED CANON (story bot, doc 03b §§5–10; Gage's call, collab log
## 2026-10-03 — implement exactly this, invent no story):
##   - Form 5/6 fires spore-tipped needles (Necro/Eterni).
##   - An infected creature's death sprouts a fruit plant.
##   - The fruit's traits = a random 1–3 sample of the host creature's
##     traits + tree lean.
##   - Harvesting the plant yields a fruit feeding the feeding loop.
##   - achievements.gd notify_spore_harvest fires on the FIRST harvest of
##     a spore-spawned plant.
##
## Design decisions (wiring — flagged, not hidden):
##   - Firing path: field combat (scythe.gd). When the player's form is 5
##     or 6, scythe hits are needle strikes: the target is infected. Only
##     targets that supply a creature snapshot are infected — traitless
##     props/dummies/invaders never grow fruit plants (canon says a
##     *creature's* death sprouts the plant).
##   - Battle seam: infect_unit() tags a BattleUnit for the future
##     Mollosar-needle battle beat; battle.gd _on_enemy_fainted() runs the
##     death hook, and a fainted foe counts as the death for this system
##     (documented choice: the spore doesn't distinguish faint from death).
##   - Infection marker: BattleUnit.spore_infected / .spore_lean; field
##     nodes via meta "spore_host" ({infected, lean, snapshot}).
##   - Needle lean: Necro/Eterni per canon. When the caller doesn't name a
##     lean, it alternates necrolean/eternilean per save (tuning
##     placeholder — the story bot can lock it to a chapter beat later).
##     The plant's tree_lean = the needle's lean; the harvested fruit's
##     lean is overridden to the tree lean (the fruit is of the spore
##     tree, not a generic concoction draw).
##   - Trait sampling: expressed (non-"bare") host traits, shuffled with a
##     seeded rng, 1–3 sampled (fewer when the host has fewer). Stored on
##     the plant and copied onto the harvested fruit as "host_traits" for
##     the future Still (trait extraction) — nothing consumes them here.
##   - Spore-plant fruit rows: host "spore_growth" in data/fruits.json
##     ([WIRING] placeholder row, story-bot owned). spore_chance 0.0 so a
##     spore fruit never chains a second infection (tuning placeholder).
##   - Plants are state records (state["spore"]["plants"]); harvesting is
##     the harvest_plant() API — room interactables call it when the
##     story bot's plant visuals/interact land.
##   - Boss seam (§12 canon): a warded target fails the needle. Field
##     nodes opt in via meta "spore_warded" == true; creature snapshots
##     may carry "warded": true. Per-phase vulnerable flags are story
##     beats, not wiring.
##
## Out of scope (do NOT build here): the Still (trait extraction),
## blacksmith's egg / Flint's dragon egg.
##
## No class_name / autoload on purpose: consumers preload this script, so it
## works in headless -s test scripts too (autoloads don't load there).
##   const SporeNeedle = preload("res://scripts/spore_needle.gd")

const CreatureData = preload("res://scripts/creature_data.gd")
const FeedingLoop = preload("res://scripts/feeding_loop.gd")

## Forms whose attacks fire spore-tipped needles (locked canon).
const SPORE_FORMS := [5, 6]

## Feeding-loop host id for spore-grown plants (data/fruits.json row).
const HOST_PLANT_ID := "spore_growth"

## Needle leans (canon: Necro/Eterni spore needles).
const NEEDLE_LEANS := ["necrolean", "eternilean"]

## Plant ids look like "sporeplant_<n>".
const PLANT_ID_FMT := "sporeplant_%d"

const MSG_NOT_SPORE_FORM := "[WIRING] The needles only fly in spore form."
const MSG_NO_CREATURE := "[WIRING] No creature there to infect."
const MSG_WARDED := "[WIRING] The needle shatters on the ward."
const MSG_INFECTED := "[WIRING] Spore-tipped needle strikes true."
const MSG_PLANT_GREW := "[WIRING] A fruit plant sprouts from the fallen creature."
const MSG_HARVESTED := "[WIRING] Harvested a spore-grown fruit."

static var _rng := RandomNumberGenerator.new()
static var _plant_seq := 0


## Test hook: seed the RNG for deterministic trait sampling.
static func set_seed(s: int) -> void:
	_rng.seed = s


static func _default_stats() -> Dictionary:
	return {
		"needles_fired": 0, "infections": 0,
		"plants_grown": 0, "plants_harvested": 0,
	}


## The spore state dict inside a game-state holder. Created lazily so old
## saves pick it up on load.
static func _data(gs) -> Dictionary:
	var s: Dictionary = gs.state
	if not s.has("spore") or not (s["spore"] is Dictionary):
		s["spore"] = {"plants": [], "stats": _default_stats(), "last_lean": ""}
	var d: Dictionary = s["spore"]
	if not (d.get("plants") is Array):
		d["plants"] = []
	if not (d.get("stats") is Dictionary):
		d["stats"] = _default_stats()
	var st: Dictionary = d["stats"]
	for k in _default_stats().keys():
		if not st.has(k):
			st[k] = _default_stats()[k]
	if not d.has("last_lean"):
		d["last_lean"] = ""
	return d


## True when the player's current form fires spore-tipped needles.
## Null-safe (headless / no GameState -> false).
static func can_fire(gs) -> bool:
	if gs == null:
		return false
	if not (gs is Object) or not gs.has_method("get_form"):
		return false
	return SPORE_FORMS.has(int(gs.get_form()))


## Next needle lean when the caller doesn't name one: alternates
## Necro/Eterni per save (tuning placeholder, see header).
static func _next_lean(gs) -> String:
	var d := _data(gs)
	var last := str(d.get("last_lean", ""))
	var nxt: String = NEEDLE_LEANS[1] if last == NEEDLE_LEANS[0] else NEEDLE_LEANS[0]
	d["last_lean"] = nxt
	return nxt


static func _valid_lean(lean: String) -> bool:
	return NEEDLE_LEANS.has(lean)


## Creature snapshot for a field target. Field creature enemies implement
## spore_host_snapshot() -> {creature_id, name, traits}; BattleUnits are
## handled via battle_snapshot(). Returns {} for non-creatures (dummies,
## invaders, props) — they can never be infected.
static func host_snapshot(target) -> Dictionary:
	if target == null:
		return {}
	var o := target as Object
	if o == null:
		return {}
	if o.has_method("spore_host_snapshot"):
		var snap = o.spore_host_snapshot()
		if snap is Dictionary:
			return (snap as Dictionary).duplicate(true)
	return {}


## Snapshot for a BattleUnit: {creature_id, name, traits, infected, lean}.
static func battle_snapshot(unit) -> Dictionary:
	var out := {"creature_id": "", "name": "", "traits": {},
		"infected": false, "lean": ""}
	if unit == null:
		return out
	var o := unit as Object
	if o == null:
		return out
	var cid := str(o.get("creature_id"))
	if cid == "":
		return out
	out["creature_id"] = cid
	CreatureData.ensure_loaded()
	var c: Dictionary = CreatureData.get_creature(cid)
	out["name"] = str(o.get("display_name") if str(o.get("display_name")) != "" else c.get("name", cid))
	out["traits"] = (c.get("traits", {}) as Dictionary).duplicate(true)
	out["infected"] = bool(o.get("spore_infected"))
	out["lean"] = str(o.get("spore_lean"))
	return out


static func _is_warded(target, snapshot: Dictionary) -> bool:
	if bool(snapshot.get("warded", false)):
		return true
	var o := target as Object
	if o != null and o.has_method("get_meta"):
		# get_meta with a default avoids errors on nodes without the key.
		return bool(o.get_meta("spore_warded", false))
	return false


## Tag a BattleUnit as spore-infected (the battle firing beat lands later;
## this is the seam). Returns false for null/unknown units.
static func infect_unit(unit, lean: String = "") -> bool:
	var o := unit as Object
	if o == null or str(o.get("creature_id")) == "":
		return false
	var use_lean := lean if _valid_lean(lean) else NEEDLE_LEANS[0]
	o.set("spore_infected", true)
	o.set("spore_lean", use_lean)
	return true


## Fire one spore-tipped needle at a field target: infects it (when it is
## a creature) and arms the death watch. Returns
## {"ok", "infected", "lean", "reason", "msg"}.
static func fire_needle(gs, target, needle_lean: String = "") -> Dictionary:
	var fail := {"ok": false, "infected": false, "lean": "", "reason": "", "msg": ""}
	if not can_fire(gs):
		fail["reason"] = "not_spore_form"
		fail["msg"] = MSG_NOT_SPORE_FORM
		return fail
	var snapshot := host_snapshot(target)
	if snapshot.is_empty():
		fail["reason"] = "no_creature"
		fail["msg"] = MSG_NO_CREATURE
		return fail
	if _is_warded(target, snapshot):
		fail["reason"] = "warded"
		fail["msg"] = MSG_WARDED
		return fail
	var lean := needle_lean if _valid_lean(needle_lean) else _next_lean(gs)
	var d := _data(gs)
	var st: Dictionary = d["stats"]
	st["needles_fired"] = int(st.get("needles_fired", 0)) + 1
	st["infections"] = int(st.get("infections", 0)) + 1
	var o := target as Object
	if o != null and o.has_method("set_meta"):
		o.set_meta("spore_host", {
			"infected": true, "lean": lean,
			"snapshot": snapshot,
		})
		_watch(gs, target)
	return {"ok": true, "infected": true, "lean": lean, "reason": "", "msg": MSG_INFECTED}


## Connect the target's died signal (once) so an infected creature's death
## grows the plant without every death listener changing. Null-safe:
## targets without a died signal are simply not watched (their death path
## — e.g. battle — calls on_creature_death explicitly).
static func _watch(gs, target) -> void:
	var o := target as Object
	if o == null or not o.has_signal("died"):
		return
	if o.has_method("has_meta") and bool(o.get_meta("spore_watched", false)):
		return
	if o.has_method("set_meta"):
		o.set_meta("spore_watched", true)
	var on_died := func(_node) -> void:
		_on_field_death(gs, target)
	o.connect("died", on_died)


## Field death resolution: read the stored infection off the dead target.
static func _on_field_death(gs, target) -> void:
	var o := target as Object
	if o == null or not o.has_method("get_meta"):
		return
	var marker: Dictionary = o.get_meta("spore_host", {})
	if marker.is_empty() or not bool(marker.get("infected", false)):
		return
	var snapshot: Dictionary = (marker.get("snapshot", {}) as Dictionary).duplicate(true)
	snapshot["lean"] = str(marker.get("lean", ""))
	on_creature_death(gs, snapshot)


## The death hook. `host` is a creature snapshot with an "infected" flag
## (field: from the spore_host meta; battle: battle_snapshot()). When the
## host was infected, a fruit plant sprouts. Null-safe: no state -> no
## plant. Returns {"grew": bool, "plant": Dictionary, "reason": String}.
static func on_creature_death(gs, host: Dictionary) -> Dictionary:
	if gs == null:
		return {"grew": false, "plant": {}, "reason": "no_state"}
	if host.is_empty() or not bool(host.get("infected", false)):
		return {"grew": false, "plant": {}, "reason": "not_infected"}
	var plant := grow_plant(gs, host)
	return {"grew": true, "plant": plant, "reason": ""}


## Grow the fruit plant from an infected host's death. Samples 1–3 of the
## host's expressed traits; the tree lean = the needle's lean. Returns the
## plant record (live reference into state).
static func grow_plant(gs, host: Dictionary) -> Dictionary:
	var d := _data(gs)
	_plant_seq += 1
	var plant_id := PLANT_ID_FMT % _plant_seq
	var seed := int(abs(hash(str(host.get("creature_id", "")) + plant_id)))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var lean := str(host.get("lean", ""))
	if not _valid_lean(lean):
		lean = NEEDLE_LEANS[0]
	var plant := {
		"plant_id": plant_id,
		"host_creature_id": str(host.get("creature_id", "")),
		"host_name": str(host.get("name", "")),
		"fruit_traits": _sample_traits(host.get("traits", {}), rng),
		"tree_lean": lean,
		"seed": seed,
		"harvested": false,
	}
	(d["plants"] as Array).append(plant)
	var st: Dictionary = d["stats"]
	st["plants_grown"] = int(st.get("plants_grown", 0)) + 1
	return plant


## Random 1–3 sample of the host's expressed (non-"bare") trait ids.
## Deterministic under the passed rng.
static func _sample_traits(traits, rng: RandomNumberGenerator) -> Array:
	var expressed: Array = []
	if traits is Dictionary:
		for slot in (traits as Dictionary).keys():
			var tid := str((traits as Dictionary)[slot])
			if tid != "" and tid != "bare":
				expressed.append(tid)
	# Fisher–Yates shuffle with the caller's rng.
	for i in range(expressed.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = expressed[i]
		expressed[i] = expressed[j]
		expressed[j] = tmp
	var n: int = mini(3, expressed.size())
	return expressed.slice(0, n)


## Live plant records (duplicates — safe for UI; harvest via
## harvest_plant()).
static func plants(gs) -> Array:
	return (_data(gs)["plants"] as Array).duplicate(true)


static func _find_plant(d: Dictionary, plant_id: String) -> Dictionary:
	for p in (d["plants"] as Array):
		if str((p as Dictionary).get("plant_id", "")) == plant_id:
			return p
	return {}


## Harvest a spore-grown plant: yields a fruit through the feeding loop.
## The fruit's lean is the plant's tree lean and it carries the sampled
## host traits (for the future Still). The FIRST harvest of a spore plant
## fires achievements.gd notify_spore_harvest. Returns
## {"ok", "reason", "fruit_id", "first_harvest", "msg"}.
static func harvest_plant(gs, plant_id: String) -> Dictionary:
	var fail := {"ok": false, "reason": "", "fruit_id": "", "first_harvest": false, "msg": ""}
	var d := _data(gs)
	var plant := _find_plant(d, plant_id)
	if plant.is_empty():
		fail["reason"] = "no_plant"
		return fail
	if bool(plant.get("harvested", false)):
		fail["reason"] = "already_harvested"
		return fail
	var fruit := FeedingLoop.pick_fruit(HOST_PLANT_ID, int(plant.get("seed", 0)))
	if fruit.is_empty():
		fail["reason"] = "no_host_row"
		return fail
	# The fruit is of the spore tree: lean = tree lean, and it carries the
	# sampled host traits for the future Still (nothing consumes them here).
	fruit["lean"] = str(plant.get("tree_lean", ""))
	fruit["host_traits"] = (plant.get("fruit_traits", []) as Array).duplicate(true)
	fruit["spore_plant_id"] = plant_id
	var fruit_id := FeedingLoop.carry(gs, fruit)
	if fruit_id == "":
		fail["reason"] = "carry_failed"
		return fail
	plant["harvested"] = true
	var st: Dictionary = d["stats"]
	st["plants_harvested"] = int(st.get("plants_harvested", 0)) + 1
	var first := int(st.get("plants_harvested", 0)) == 1
	if first:
		_ach_spore_harvest(gs)
	return {"ok": true, "reason": "", "fruit_id": fruit_id,
		"first_harvest": first, "msg": MSG_HARVESTED}


## Fire the registered-but-dormant spore_harvest hook (null-safe: gs may
## be a stub in headless tests).
static func _ach_spore_harvest(gs) -> void:
	if gs == null:
		return
	if gs is Object:
		var ach = gs.get("achievements")
		if ach != null and (ach as Object).has_method("notify_spore_harvest"):
			(ach as Object).notify_spore_harvest()
			return
	if gs is Object and (gs as Object).has_method("unlock_achievement"):
		(gs as Object).unlock_achievement("spore_harvest")


## Spore stats (duplicates).
static func stats(gs) -> Dictionary:
	return (_data(gs)["stats"] as Dictionary).duplicate()


# --- Save / load -----------------------------------------------------------
## Serialization into the game-state dict (JSON-safe: plain types only).

static func save_data(gs) -> Dictionary:
	return (_data(gs)).duplicate(true)


## Restore from a save-data dict. Validates minimal shape; repairs stats
## defaults. Returns false (no write) on malformed data.
static func load_data(gs, data: Dictionary) -> bool:
	if data.is_empty():
		return false
	if not (data.get("plants") is Array):
		return false
	if not (data.get("stats") is Dictionary):
		return false
	gs.state["spore"] = data.duplicate(true)
	_data(gs)
	return true
