extends RefCounted
## Fruit feeding loop (wiring).
##
## LOCKED CANON (Sweet Potato Creature, via the collab log — build exactly this):
##   1. Fruit is a RANDOM CONCOCTION of its HOST PLANT — each fruit's
##      identity/effects derive from its host plant, randomized.
##   2. Lean types: NecroLean / Death / EterniLean ("lean" is a substance in
##      the fruit). LUNA SMELLS THE LEAN — luna_smell() reveals the lean
##      type. (The Luna comment line itself is story text: data/ui_text.json
##      "feeding" entries are [WIRING]-flagged placeholders, verbatim lines
##      still needed from Sweet Potato Creature.)
##   3. POWER HIDDEN UNTIL EATEN — a carried fruit's power is hidden
##      (describe() reports "unknown") until eat() reveals and applies it.
##   4. 1,200-STEP ROT TIMER — a carried fruit rots after 1,200 steps
##      (on_steps_taken()); rotted fruit cannot be eaten.
##   5. SPORE INFECTION grows a GRAVEbloom ON EVERY DEFEAT — eating
##      spore-bearing fruit infects the carrier; on player defeat the
##      infection grows a gravebloom. Canon constraint (doc 03b):
##      graveblooms grow ONLY from player defeats — so this system NEVER
##      bumps the "gravebloom_grown" counter. The defeat flow calls
##      FeedingLoop.consume_defeat_infection(gs) and then
##      GameState.on_player_defeat() EXACTLY ONCE. The infection is consumed
##      on defeat. There is no parallel growth path.
##
## Fruit rows are STORY-BOT OWNED data (data/fruits.json); this script only
## resolves, carries, smells, eats, rots, and tracks infection.
##
## Design decisions (wiring — flagged, not hidden):
##   - Fruit instances live in state["feeding"]["carried"] (Array of fruit
##     dicts), NOT in the counted inventory (state["inventory"] is
##     item_id -> count; a concoction is unique per fruit, so instance
##     dicts are the model). No items.json entries were seeded for fruit.
##   - pick_fruit() does NOT assign an instance id; carry() assigns
##     "fruit_<host>_<n>" from a per-save picked counter. Determinism:
##     same host + seed -> identical concoction dicts.
##   - Infection is singular: eating a second spore fruit replaces the
##     active infection (latest wins), reported in the eat() result.
##   - A spore defeat does NOT grow an extra bloom: every defeat grows one
##     gravebloom; consume_defeat_infection() only marks whether this
##     defeat's bloom was spore-grown (result + feeding stats). The
##     "gravebloom_grown" counter is untouched here — the one and only
##     growth path is GameState.on_player_defeat().
##   - Spore-bearing is VISIBLE in describe() (a physical property of the
##     fruit); only the power/effect is hidden until eaten.
##   - luna_smell() counts a reveal only when lean flips unknown -> known
##     (re-smelling is idempotent, no stat spam).
##   - The story beat "harvest a fruit plant grown from a spore-infected
##     kill" (achievements.gd notify_spore_harvest) is LATER harvest wiring,
##     not this system — nothing here unlocks it.
##   - eat_prompt()/luna lines live in data/ui_text.json ("feeding"
##     section) and are [WIRING]-flagged placeholders; never hardcode prose.
##
## No class_name / autoload on purpose: consumers preload this script, so it
## works in headless -s test scripts too (autoloads don't load there).
##   const FeedingLoop = preload("res://scripts/feeding_loop.gd")

const UIText = preload("res://scripts/ui_text.gd")

const FRUITS_PATH := "res://data/fruits.json"

## Locked: a carried fruit rots after this many steps.
const ROT_STEPS := 1200

## Locked lean types.
const LEAN_NECRO := "necrolean"
const LEAN_DEATH := "death"
const LEAN_ETERN := "eternilean"
const LEAN_TYPES := [LEAN_NECRO, LEAN_DEATH, LEAN_ETERN]

## Effect types the wiring applies (closed set — story-bot rows only pick
## from these until new types get wiring).
const EFFECT_HEAL := "heal_vigor"
const EFFECT_CREDITS := "grant_credits"

static var _fruits_cache: Dictionary = {}


static func _load_fruits() -> Dictionary:
	if not _fruits_cache.is_empty():
		return _fruits_cache
	if not FileAccess.file_exists(FRUITS_PATH):
		return {}
	var f := FileAccess.open(FRUITS_PATH, FileAccess.READ)
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		_fruits_cache = parsed
	return _fruits_cache


## Host-plant rows (story-bot owned). {host_id: row}
static func hosts() -> Dictionary:
	return _load_fruits().get("hosts", {})


## Seeded host plant ids.
static func host_ids() -> Array:
	return hosts().keys()


static func _default_stats() -> Dictionary:
	return {
		"picked": 0, "eaten": 0, "rotted": 0, "smelled": 0,
		"spore_defeats": 0, "last_eaten": {},
	}


## The feeding state dict inside a game-state holder (a GameState node or
## any object with a .state Dictionary). Shape is created lazily so old
## saves pick it up on load.
static func _data(gs) -> Dictionary:
	var s: Dictionary = gs.state
	if not s.has("feeding") or not (s["feeding"] is Dictionary):
		s["feeding"] = {"carried": [], "infection": {}, "stats": _default_stats()}
	var d: Dictionary = s["feeding"]
	if not (d.get("carried") is Array):
		d["carried"] = []
	if not (d.get("infection") is Dictionary):
		d["infection"] = {}
	if not (d.get("stats") is Dictionary):
		d["stats"] = _default_stats()
	var st: Dictionary = d["stats"]
	for k in _default_stats().keys():
		if not st.has(k):
			st[k] = _default_stats()[k]
	return d


static func _weighted_pick(rng: RandomNumberGenerator, entries, fallback):
	if entries is Dictionary:
		var total := 0.0
		for k in (entries as Dictionary).keys():
			total += float((entries as Dictionary)[k])
		if total <= 0.0:
			return fallback
		var r := rng.randf_range(0.0, total)
		var acc := 0.0
		for k in (entries as Dictionary).keys():
			acc += float((entries as Dictionary)[k])
			if r <= acc:
				return k
		return fallback
	if entries is Array:
		var total := 0.0
		for e in (entries as Array):
			total += float((e as Dictionary).get("weight", 0))
		if total <= 0.0:
			return fallback
		var r := rng.randf_range(0.0, total)
		var acc := 0.0
		for e in (entries as Array):
			acc += float((e as Dictionary).get("weight", 0))
			if r <= acc:
				return (e as Dictionary).duplicate(true)
		return fallback
	return fallback


static func _array_pick(rng: RandomNumberGenerator, arr: Array, fallback: String) -> String:
	if arr.is_empty():
		return fallback
	return str(arr[rng.randi_range(0, arr.size() - 1)])


## Build a fruit: a random concoction of its host plant. Seeded —
## identical host + seed always yields the identical concoction dict.
## Returns {} for an unknown host. The returned dict has no instance id;
## carry() assigns one.
static func pick_fruit(host_plant: String, seed: int) -> Dictionary:
	var all := hosts()
	if not all.has(host_plant):
		return {}
	var row: Dictionary = all[host_plant]
	var rng := RandomNumberGenerator.new()
	rng.seed = int(abs(hash(host_plant)) + int(seed) * 7919)
	var lean := str(_weighted_pick(rng, row.get("lean_weights", {}), LEAN_NECRO))
	if not LEAN_TYPES.has(lean):
		lean = LEAN_NECRO
	var epithet := _array_pick(rng, row.get("epithets", []), "Pale")
	var effect: Dictionary = _weighted_pick(rng, row.get("effects", []), {"type": EFFECT_HEAL, "amount": 1})
	if not (effect is Dictionary):
		effect = {"type": EFFECT_HEAL, "amount": 1}
	var spore := rng.randf() < float(row.get("spore_chance", 0.0))
	return {
		"host_plant": host_plant,
		"name": "%s %s" % [str(row.get("name", host_plant)), epithet],
		"lean": lean,
		"lean_known": false,
		"effect": effect,
		"power_hidden": true,
		"spore": spore,
		"steps_carried": 0,
		"rotted": false,
	}


## Carry a fruit (assigns the instance id). Returns the fruit_id, or ""
## when the fruit is malformed / unknown host.
static func carry(gs, fruit: Dictionary) -> String:
	if fruit.is_empty():
		return ""
	if not hosts().has(str(fruit.get("host_plant", ""))):
		return ""
	var d := _data(gs)
	var n := int((d["stats"] as Dictionary).get("picked", 0)) + 1
	(d["stats"] as Dictionary)["picked"] = n
	var inst: Dictionary = fruit.duplicate(true)
	inst["fruit_id"] = "fruit_%s_%d" % [str(fruit.get("host_plant", "")), n]
	(d["carried"] as Array).append(inst)
	return str(inst["fruit_id"])


## Carried fruit instances (duplicates — safe for UI; use the id-keyed
## mutators to change state).
static func carried(gs) -> Array:
	return (_data(gs)["carried"] as Array).duplicate(true)


## Live reference to the carried instance (for internal mutation), or {}.
static func _find(d: Dictionary, fruit_id: String) -> Dictionary:
	for f in (d["carried"] as Array):
		if str((f as Dictionary).get("fruit_id", "")) == fruit_id:
			return f
	return {}


static func _find_index(d: Dictionary, fruit_id: String) -> int:
	var i := 0
	for f in (d["carried"] as Array):
		if str((f as Dictionary).get("fruit_id", "")) == fruit_id:
			return i
		i += 1
	return -1


## Luna smells the lean: reveals the fruit's lean type. Idempotent —
## re-smelling returns the same lean without re-counting the stat.
## Returns {"ok": bool, "lean": String, "line": String}. The line is the
## [WIRING]-flagged placeholder from data/ui_text.json (story text).
static func luna_smell(gs, fruit_id: String) -> Dictionary:
	var d := _data(gs)
	var f := _find(d, fruit_id)
	if f.is_empty():
		return {"ok": false, "lean": "", "line": ""}
	var lean := str(f.get("lean", LEAN_NECRO))
	if not bool(f.get("lean_known", false)):
		f["lean_known"] = true
		var st: Dictionary = d["stats"]
		st["smelled"] = int(st.get("smelled", 0)) + 1
	return {"ok": true, "lean": lean, "line": UIText.feeding("luna_smell_" + lean)}


## UI-safe projection of a fruit. The power stays "unknown" until eaten;
## the lean stays "?" until Luna smells it. Spore-bearing is visible.
static func describe(fruit: Dictionary) -> Dictionary:
	var lean := "?"
	if bool(fruit.get("lean_known", false)):
		lean = str(fruit.get("lean", "?"))
	var power := "unknown"
	if not bool(fruit.get("power_hidden", true)):
		power = effect_summary(fruit.get("effect", {}))
	return {
		"fruit_id": str(fruit.get("fruit_id", "")),
		"name": str(fruit.get("name", "?")),
		"host_plant": str(fruit.get("host_plant", "")),
		"lean": lean,
		"power": power,
		"spore": bool(fruit.get("spore", false)),
		"rotted": bool(fruit.get("rotted", false)),
		"steps_carried": int(fruit.get("steps_carried", 0)),
		"steps_until_rot": maxi(0, ROT_STEPS - int(fruit.get("steps_carried", 0))),
	}


## Short summary of a resolved effect (used post-eat; never pre-eat).
static func effect_summary(effect: Dictionary) -> String:
	match str(effect.get("type", "")):
		EFFECT_HEAL:
			return "heal %d vigor" % int(effect.get("amount", 0))
		EFFECT_CREDITS:
			return "grant %d soul credits" % int(effect.get("amount", 0))
	return "unknown effect"


static func _apply_effect(gs, effect: Dictionary) -> Dictionary:
	match str(effect.get("type", "")):
		EFFECT_HEAL:
			var p: Dictionary = gs.state["player"]
			var cur := int(p.get("vigor", 0))
			var vmax := int(p.get("vigor_max", cur))
			var heal := mini(int(effect.get("amount", 0)), maxi(0, vmax - cur))
			gs.set_vigor(cur + heal)
			return {"type": EFFECT_HEAL, "healed": heal}
		EFFECT_CREDITS:
			var n := int(effect.get("amount", 0))
			gs.add_soul_credits(n)
			return {"type": EFFECT_CREDITS, "credits": n}
	return {"type": str(effect.get("type", "")), "applied": false}


## Eat a carried fruit: reveals the hidden power, applies it, removes the
## fruit. Spore-bearing fruit infects the carrier. Rotted or missing fruit
## is refused. Returns {"ok", "reason", "effect", "applied", "infected",
## "replaced_infection", "lean"}.
static func eat(gs, fruit_id: String) -> Dictionary:
	var d := _data(gs)
	var idx := _find_index(d, fruit_id)
	if idx < 0:
		return {"ok": false, "reason": "missing", "effect": {}, "applied": {}, "infected": false, "replaced_infection": false, "lean": ""}
	var f: Dictionary = (d["carried"] as Array)[idx]
	if bool(f.get("rotted", false)):
		return {"ok": false, "reason": "rotted", "effect": {}, "applied": {}, "infected": false, "replaced_infection": false, "lean": ""}
	(d["carried"] as Array).remove_at(idx)
	var effect: Dictionary = (f.get("effect", {}) as Dictionary).duplicate(true)
	var applied := _apply_effect(gs, effect)
	var st: Dictionary = d["stats"]
	st["eaten"] = int(st.get("eaten", 0)) + 1
	st["last_eaten"] = effect
	var infected := false
	var replaced := false
	if bool(f.get("spore", false)):
		if not (d["infection"] as Dictionary).is_empty():
			replaced = true
		d["infection"] = {
			"fruit_id": fruit_id,
			"host_plant": str(f.get("host_plant", "")),
			"lean": str(f.get("lean", LEAN_NECRO)),
		}
		infected = true
	return {
		"ok": true, "reason": "", "effect": effect, "applied": applied,
		"infected": infected, "replaced_infection": replaced,
		"lean": str(f.get("lean", LEAN_NECRO)),
	}


## Advance the rot timer on every carried fruit. Fruits at ROT_STEPS rot.
## Returns {"rotted": [fruit_ids newly rotted]}.
static func on_steps_taken(gs, n: int) -> Dictionary:
	var d := _data(gs)
	var newly: Array = []
	for f in (d["carried"] as Array):
		if bool((f as Dictionary).get("rotted", false)):
			continue
		(f as Dictionary)["steps_carried"] = int((f as Dictionary).get("steps_carried", 0)) + n
		if int((f as Dictionary).get("steps_carried", 0)) >= ROT_STEPS:
			(f as Dictionary)["rotted"] = true
			newly.append(str((f as Dictionary).get("fruit_id", "")))
	if not newly.is_empty():
		var st: Dictionary = d["stats"]
		st["rotted"] = int(st.get("rotted", 0)) + newly.size()
	return {"rotted": newly}


## The eat prompt string for a fruit (data string, never hardcoded prose).
## Verbatim locked by Sweet Potato Creature (collab log 2026-10-05).
static func eat_prompt(fruit_name: String) -> String:
	return UIText.feeding("eat_prompt").replace("{fruit}", fruit_name)


# --- Spore infection ------------------------------------------------------
## Active spore infection ({} when none). Set by eat(), consumed by
## consume_defeat_infection().

static func has_spore_infection(gs) -> bool:
	return not (_data(gs)["infection"] as Dictionary).is_empty()


static func get_infection(gs) -> Dictionary:
	return (_data(gs)["infection"] as Dictionary).duplicate(true)


static func clear_spore_infection(gs) -> void:
	_data(gs)["infection"] = {}


## Defeat hook. Consumes the active spore infection (if any) and reports
## whether this defeat's gravebloom is spore-grown.
##
## NEVER bumps "gravebloom_grown" — the ONLY growth path is
## GameState.on_player_defeat() (canon: graveblooms grow ONLY from player
## defeats, doc 03b). The defeat flow calls this first, then
## gs.on_player_defeat() EXACTLY ONCE — that single bump counts the
## (spore-grown) gravebloom. Calling both on_player_defeat and this hook
## twice, or any parallel counter bump, would double-count.
##
## Returns {"spore_bloom": bool, "host_plant": String (when spore_bloom)}.
static func consume_defeat_infection(gs) -> Dictionary:
	var d := _data(gs)
	var inf: Dictionary = d["infection"]
	if inf.is_empty():
		return {"spore_bloom": false}
	var host := str(inf.get("host_plant", ""))
	d["infection"] = {}
	var st: Dictionary = d["stats"]
	st["spore_defeats"] = int(st.get("spore_defeats", 0)) + 1
	return {"spore_bloom": true, "host_plant": host}


# --- Save / load -----------------------------------------------------------
## Serialization into the game-state dict (JSON-safe: plain types only).

static func save_data(gs) -> Dictionary:
	return (_data(gs)).duplicate(true)


## Restore from a save-data dict. Validates minimal shape; repairs stats
## defaults. Returns false (no write) on malformed data.
static func load_data(gs, data: Dictionary) -> bool:
	if data.is_empty():
		return false
	if not (data.get("carried") is Array):
		return false
	if not (data.get("infection") is Dictionary):
		return false
	gs.state["feeding"] = data.duplicate(true)
	_data(gs)
	return true
