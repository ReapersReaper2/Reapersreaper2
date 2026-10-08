extends RefCounted
## Standard creature breeding & rearing for Reaper's Reaper.
##
## LOCKED RULES (Gage — do not deviate):
##   - One male + one female ONLY. No exceptions. The gate refuses
##     same-sex pairs with a clear message.
##   - NO hybrid-part fusion. Offspring inherit whole parts from their
##     parents via dominance rolls — a part is always one parent's part,
##     never a blend of the two.
##
## Pipeline: breed (M+F) -> Egg (incubates, e.g. at shrine rests) ->
## Hatchling -> Juvenile -> Adult (feed + party presence grow it).
## Offspring raised from an egg get a Journey Gift (small loyalty bonus).
##
## Data model (all JSON-safe, lives in GameState.state):
##   state["nursery"]: Array of egg dicts:
##     {egg_id, sire: snapshot, dam: snapshot, steps_total, steps_done}
##   A snapshot: {creature_id, traits: {slot: trait_id}, genes: {pair: [a,b]},
##     base: {vigor, might, guard, speed}}
##   Offspring party entries (see party.gd) gain:
##     sex ("M"/"F"), growth_stage ("hatchling"/"juvenile"/"adult"),
##     growth_points (int), traits_override, part_donors ({slot: {"species":
##     species_id, "part_id": trait_id}} — donor provenance for the armor
##     accumulator), genes_override, base_override,
##     journey_gift (bool), parents {sire_id, dam_id}.
## Entries without growth_stage are treated as adults (wild-caught/legacy).
## Entries without part_donors are treated as self-donated (the entry's own
## species is the DonorSpecies for every slot).
##
## No class_name / autoload on purpose: consumers preload this script, so it
## works in headless -s test scripts too (autoloads don't load there).
##   const Breeding = preload("res://scripts/breeding.gd")

const CreatureData = preload("res://scripts/creature_data.gd")
const Party = preload("res://scripts/party.gd")

## Part slots, in canon order (9-slot model, signed off 2026-10-04:
## root/stem/bloom/leafset/appendage/armor/accent plus eyes and face).
## Every creature instance carries all 9 slots.
const SLOTS := ["root", "stem", "bloom", "leafset", "appendage", "armor", "accent", "eyes", "face"]

const STAGE_HATCHLING := "hatchling"

## Creature id for the armor plant (breeding.gd's gardener tracking keys
## off this; the species data lands with the armor-plant creature line).
const ARMOR_PLANT_ID := "armor_plant"
const STAGE_JUVENILE := "juvenile"
const STAGE_ADULT := "adult"

## Tuning placeholders (not canon).
const GROWTH_TO_JUVENILE := 30
const GROWTH_TO_ADULT := 70
const FEED_GROWTH := 12        # growth points per feed action
const PARTY_TICK_GROWTH := 3   # growth per day while in the active party
const EGG_STEPS := 20          # incubation steps per egg
const EGG_STEPS_PER_DAY := 7   # incubation progress per shrine rest (day boundary)
## Journey Gift: small flat loyalty bonus for egg-raised creatures.
const GIFT_BONUS := {"vigor": 3, "might": 1, "guard": 1, "speed": 1}

const MSG_SAME_SEX := "Breeding needs one male and one female. No exceptions."
const MSG_SAME_SLOT := "Pick two different creatures."
const MSG_NOT_ADULT := "Only adults can breed — raise the young one first."
const MSG_NO_SEX := "That creature's sex is unknown."

static var _rng := RandomNumberGenerator.new()
static var _egg_seq := 0


## Test hook: seed the RNG for deterministic inheritance rolls.
static func set_seed(s: int) -> void:
	_rng.seed = s


static func _nursery(gs: Node) -> Array:
	if not gs.state.has("nursery") or not (gs.state["nursery"] is Array):
		gs.state["nursery"] = []
	return gs.state["nursery"]


## Sex of a party entry ("M"/"F"/""). Assigns + persists a random sex when
## missing (legacy entries predate the sex field).
static func sex_of(entry: Dictionary) -> String:
	var s := str(entry.get("sex", ""))
	if s == "M" or s == "F":
		return s
	s = "M" if _rng.randf() < 0.5 else "F"
	entry["sex"] = s
	return s


static func is_adult(entry: Dictionary) -> bool:
	var st := str(entry.get("growth_stage", STAGE_ADULT))
	return st == STAGE_ADULT


static func growth_stage_of(points: int) -> String:
	if points >= GROWTH_TO_ADULT:
		return STAGE_ADULT
	if points >= GROWTH_TO_JUVENILE:
		return STAGE_JUVENILE
	return STAGE_HATCHLING


## The breeding gate. Returns {ok: bool, msg: String}.
static func can_breed(gs: Node, i: int, j: int) -> Dictionary:
	if not Party.is_valid_index(gs, i) or not Party.is_valid_index(gs, j):
		return {"ok": false, "msg": "Pick two creatures from your party."}
	if i == j:
		return {"ok": false, "msg": MSG_SAME_SLOT}
	var a: Dictionary = Party.get_entry(gs, i)
	var b: Dictionary = Party.get_entry(gs, j)
	var sa := sex_of(a)
	var sb := sex_of(b)
	if sa == "" or sb == "":
		return {"ok": false, "msg": MSG_NO_SEX}
	if sa == sb:
		return {"ok": false, "msg": MSG_SAME_SEX}
	if not is_adult(a) or not is_adult(b):
		return {"ok": false, "msg": MSG_NOT_ADULT}
	return {"ok": true, "msg": "A fine pair."}


static func _snapshot(entry: Dictionary) -> Dictionary:
	return {
		"creature_id": str(entry.get("creature_id", "")),
		"traits": effective_traits(entry).duplicate(),
		"genes": effective_genes(entry).duplicate(true),
		"base": effective_base(entry).duplicate(),
	}


## Breed the pair at party indices i/j. Returns {ok, msg, egg} — the egg
## lands in state["nursery"]. The sire is always the male, the dam the female.
static func breed(gs: Node, i: int, j: int) -> Dictionary:
	var check := can_breed(gs, i, j)
	if not bool(check.get("ok", false)):
		return {"ok": false, "msg": str(check.get("msg", "")), "egg": {}}
	var a: Dictionary = Party.get_entry(gs, i)
	var b: Dictionary = Party.get_entry(gs, j)
	var sire := a if sex_of(a) == "M" else b
	var dam := b if sex_of(a) == "M" else a
	_egg_seq += 1
	var egg := {
		"egg_id": "egg_%d" % _egg_seq,
		"sire": _snapshot(sire),
		"dam": _snapshot(dam),
		"steps_total": EGG_STEPS,
		"steps_done": 0,
	}
	_nursery(gs).append(egg)
	return {"ok": true, "msg": "An egg! Keep it warm.", "egg": egg}


## Advance all eggs by `steps` incubation. Returns number of eggs now ready.
static func advance_eggs(gs: Node, steps: int) -> int:
	var ready := 0
	for egg in _nursery(gs):
		var e: Dictionary = egg
		e["steps_done"] = mini(int(e.get("steps_done", 0)) + steps, int(e.get("steps_total", EGG_STEPS)))
		if int(e["steps_done"]) >= int(e.get("steps_total", EGG_STEPS)):
			ready += 1
	return ready


## Day boundary hook (called from shrine rest): eggs incubate, young grow.
static func on_day_advance(gs: Node) -> void:
	advance_eggs(gs, EGG_STEPS_PER_DAY)
	tick_party_growth(gs)


## Hatch the egg at nursery index k. The hatchling joins the party (or the
## egg waits if the party is full). Returns {ok, msg, entry}.
static func hatch_egg(gs: Node, k: int) -> Dictionary:
	var n := _nursery(gs)
	if k < 0 or k >= n.size():
		return {"ok": false, "msg": "No egg there.", "entry": {}}
	var egg: Dictionary = n[k]
	if int(egg.get("steps_done", 0)) < int(egg.get("steps_total", EGG_STEPS)):
		return {"ok": false, "msg": "Not ready to hatch yet.", "entry": {}}
	var entry := _make_offspring(egg)
	if not Party.append_entry(gs, entry):
		return {"ok": false, "msg": "Your party is full — make room first.", "entry": {}}
	n.remove_at(k)
	_ach_on_hatch(gs, entry)
	return {"ok": true, "msg": "It hatched!", "entry": entry}


## Achievement beats on a successful hatch (null-safe: gs may be a stub).
static func _ach_on_hatch(gs, entry: Dictionary) -> void:
	if gs == null or not gs.has_method("unlock_achievement"):
		return
	# Steam "first_hatch" — trigger map: creature_hatched counter,
	# fire on count == 1.
	var hatched := 1
	if gs.has_method("bump_counter"):
		hatched = int(gs.bump_counter("creature_hatched"))
	if hatched == 1:
		gs.unlock_achievement("first_hatch")
	# Steam "gardener" (hidden) — trigger map: armor_plant_bred flag,
	# set when the hybridization chain completes (second armor plant).
	# Fires exactly once: the flag is set once, unlock() is idempotent.
	if str(entry.get("creature_id", "")) == ARMOR_PLANT_ID:
		if gs.has_method("get_flag") and bool(gs.get_flag("armor_plant_bred_once")):
			if gs.has_method("set_flag"):
				gs.set_flag("armor_plant_bred", true)
		elif gs.has_method("set_flag"):
			gs.set_flag("armor_plant_bred_once", true)


## Feed a growing party member. Simple feed action (tuning placeholder —
## a canon food item can add cost/bonus later). Returns {ok, msg, stage}.
static func feed(gs: Node, i: int) -> Dictionary:
	if not Party.is_valid_index(gs, i):
		return {"ok": false, "msg": "No creature there.", "stage": ""}
	var e: Dictionary = Party.get_entry(gs, i)
	if is_adult(e):
		return {"ok": false, "msg": "It's fully grown.", "stage": STAGE_ADULT}
	e["growth_points"] = int(e.get("growth_points", 0)) + FEED_GROWTH
	e["growth_stage"] = growth_stage_of(int(e["growth_points"]))
	return {"ok": true, "msg": "Fed! It looks stronger.", "stage": str(e["growth_stage"])}


## Party presence: growing members gain a little each day. Returns count grown.
static func tick_party_growth(gs: Node) -> int:
	var grown := 0
	var p: Array = Party._party(gs)
	for e in p:
		var entry: Dictionary = e
		if is_adult(entry):
			continue
		entry["growth_points"] = int(entry.get("growth_points", 0)) + PARTY_TICK_GROWTH
		entry["growth_stage"] = growth_stage_of(int(entry["growth_points"]))
		grown += 1
	return grown


## ---- inheritance (no fusion: every part is one parent's part, whole) ----

## Per-slot dominance roll: each parent's trait weighs in with its dominance
## value; the winner's trait id is inherited verbatim. Runs across all 9
## slots. Returns {"traits": {slot: trait_id}, "donors": {slot: {"species":
## species_id, "part_id": trait_id}}} — the donor map records which parent
## species each grown part came from, for the armor accumulator.
static func _inherit_traits(sire: Dictionary, dam: Dictionary) -> Dictionary:
	CreatureData.ensure_loaded()
	var traits := {}
	var donors := {}
	var st: Dictionary = sire.get("traits", {})
	var dt: Dictionary = dam.get("traits", {})
	var sire_id := str(sire.get("creature_id", ""))
	var dam_id := str(dam.get("creature_id", ""))
	for slot in SLOTS:
		var sid := str(st.get(slot, "bare"))
		var did := str(dt.get(slot, "bare"))
		if sid == did:
			traits[slot] = sid
			donors[slot] = {"species": sire_id, "part_id": sid}
			continue
		var sdom := float(CreatureData.get_trait(sid).get("dominance", 0.5))
		var ddom := float(CreatureData.get_trait(did).get("dominance", 0.5))
		var total := sdom + ddom
		var pick_sire := true
		if total <= 0.0:
			pick_sire = _rng.randf() < 0.5
		else:
			pick_sire = _rng.randf() * total < sdom
		var winner := sid if pick_sire else did
		traits[slot] = winner
		donors[slot] = {"species": sire_id if pick_sire else dam_id, "part_id": winner}
	return {"traits": traits, "donors": donors}


## Base stats: blend of the parents (uniform between them, so the offspring
## always lands inside the parental range) with natural variance.
static func _inherit_base(sire: Dictionary, dam: Dictionary) -> Dictionary:
	var out := {}
	var sb: Dictionary = sire.get("base", {})
	var db: Dictionary = dam.get("base", {})
	for stat in ["vigor", "might", "guard", "speed"]:
		var a := float(sb.get(stat, 1))
		var b := float(db.get(stat, 1))
		out[stat] = maxi(1, int(round(a + (b - a) * _rng.randf())))
	return out


## ACNH-flower-style color genetics (cosmetic only): each gene pair takes
## one allele from each parent.
static func _inherit_genes(sire: Dictionary, dam: Dictionary) -> Dictionary:
	var out := {}
	var sg: Dictionary = sire.get("genes", {})
	var dg: Dictionary = dam.get("genes", {})
	for pair in ["hue", "bloom_tint", "pattern"]:
		var sa: Array = sg.get(pair, ["?", "?"])
		var da: Array = dg.get(pair, ["?", "?"])
		out[pair] = [str(sa[int(_rng.randf() * sa.size()) % sa.size()]),
			str(da[int(_rng.randf() * da.size()) % da.size()])]
	return out


## Build the hatchling party entry. Species follows the dam (mother).
static func _make_offspring(egg: Dictionary) -> Dictionary:
	var sire: Dictionary = egg.get("sire", {})
	var dam: Dictionary = egg.get("dam", {})
	var species := str(dam.get("creature_id", "snapling"))
	var entry := Party.make_entry(species, 1)
	var inherited := _inherit_traits(sire, dam)
	entry["traits_override"] = inherited["traits"]
	# Donor provenance for the armor accumulator: which parent species each
	# grown part came from (DonorSpecies + Slot, read from this record).
	entry["part_donors"] = inherited["donors"]
	entry["genes_override"] = _inherit_genes(sire, dam)
	entry["base_override"] = _inherit_base(sire, dam)
	entry["growth_stage"] = STAGE_HATCHLING
	entry["growth_points"] = 0
	entry["journey_gift"] = true
	entry["parents"] = {"sire_id": str(sire.get("creature_id", "")),
		"dam_id": str(dam.get("creature_id", ""))}
	sex_of(entry)
	var st := derived_stats(entry, 1)
	entry["current_hp"] = st["max_hp"]
	entry["ability_ids"] = _abilities_for(entry)
	return entry


static func _abilities_for(entry: Dictionary) -> Array:
	CreatureData.ensure_loaded()
	var pseudo := {"traits": effective_traits(entry), "moves": []}
	return CreatureData.creature_abilities(pseudo)


## ---- effective (override-aware) accessors ----

static func effective_traits(entry: Dictionary) -> Dictionary:
	if entry.has("traits_override"):
		return entry["traits_override"]
	CreatureData.ensure_loaded()
	return CreatureData.get_creature(str(entry.get("creature_id", ""))).get("traits", {})


static func effective_base(entry: Dictionary) -> Dictionary:
	if entry.has("base_override"):
		return entry["base_override"]
	CreatureData.ensure_loaded()
	return CreatureData.get_creature(str(entry.get("creature_id", ""))).get("base", {})


static func effective_genes(entry: Dictionary) -> Dictionary:
	if entry.has("genes_override"):
		return entry["genes_override"]
	CreatureData.ensure_loaded()
	return CreatureData.get_creature(str(entry.get("creature_id", ""))).get("genes", {})


## Number of expressed (non-"bare") traits — the 5-9 canon range.
static func expressed_trait_count(entry: Dictionary) -> int:
	var n := 0
	for slot in effective_traits(entry):
		if str(effective_traits(entry)[slot]) != "bare":
			n += 1
	return n


## Derived battle stats for an entry, honoring overrides + Journey Gift.
## Mirrors battle_unit.gd's formula (LEVEL_GROWTH 0.08) so reared creatures
## stay consistent with caught ones.
static func derived_stats(entry: Dictionary, level: int) -> Dictionary:
	CreatureData.ensure_loaded()
	var base := effective_base(entry)
	var traits := effective_traits(entry)
	var might := 0
	var guard := 0
	for slot in traits:
		var t: Dictionary = CreatureData.get_trait(str(traits[slot]))
		might += int(t.get("might_mod", 0))
		guard += int(t.get("guard_mod", 0))
	var mult := 1.0 + float(maxi(1, level) - 1) * 0.08
	var gift: Dictionary = GIFT_BONUS if bool(entry.get("journey_gift", false)) else {}
	return {
		"max_hp": int(round(float(base.get("vigor", 20)) * mult)) + int(gift.get("vigor", 0)),
		"attack": int(round(float(base.get("might", 5) + might) * mult)) + int(gift.get("might", 0)),
		"defense": int(round(float(base.get("guard", 5) + guard) * mult)) + int(gift.get("guard", 0)),
		"speed": int(round(float(base.get("speed", 5)) * mult)) + int(gift.get("speed", 0)),
	}
