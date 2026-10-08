extends RefCounted
## Creature / trait / ability data layer for Reaper's Reaper tactical battles.
##
## Loads the canon part-trait definitions from res://data/*.json. Canon rules
## from the roster doc (03): no Pokemon-style types; every part trait carries
## Might (attack) and Guard (armor); abilities come from parts; breeding
## expresses 5-9 traits via dominance rolls (dominance values stored here,
## breeding itself is a later task).
##
## No class_name / autoload on purpose: consumers preload this script, so it
## works in headless -s test scripts too (autoloads don't load there).
##   const CreatureData = preload("res://scripts/creature_data.gd")
##
## The table itself holds no mutable state (beyond its one-time JSON cache).

static var _creatures: Dictionary = {}
static var _traits: Dictionary = {}
static var _abilities: Dictionary = {}
static var _items: Dictionary = {}
static var _shops: Dictionary = {}
static var _loaded: bool = false


static func _load_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("creature_data: cannot open " + path)
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("creature_data: bad JSON in " + path)
		return {}
	return parsed as Dictionary


static func ensure_loaded() -> void:
	if _loaded:
		return
	_creatures = _load_json("res://data/creatures.json").get("creatures", {})
	_traits = _load_json("res://data/traits.json").get("traits", {})
	_abilities = _load_json("res://data/abilities.json").get("abilities", {})
	_items = _load_json("res://data/items.json").get("items", {})
	_shops = _load_json("res://data/shop.json").get("shops", {})
	_loaded = true


static func creature_ids() -> Array:
	ensure_loaded()
	return _creatures.keys()


static func trait_ids() -> Array:
	ensure_loaded()
	return _traits.keys()


static func ability_ids() -> Array:
	ensure_loaded()
	return _abilities.keys()


static func item_ids() -> Array:
	ensure_loaded()
	return _items.keys()


static func get_creature(creature_id: String) -> Dictionary:
	ensure_loaded()
	return _creatures.get(creature_id, {})


static func get_trait(trait_id: String) -> Dictionary:
	ensure_loaded()
	return _traits.get(trait_id, {})


static func get_ability(ability_id: String) -> Dictionary:
	ensure_loaded()
	return _abilities.get(ability_id, {})


static func get_item(item_id: String) -> Dictionary:
	ensure_loaded()
	return _items.get(item_id, {})


## Trait mod totals for one creature entry: {"might": N, "guard": N}.
static func trait_mods(creature: Dictionary) -> Dictionary:
	ensure_loaded()
	var might := 0
	var guard := 0
	var traits: Dictionary = creature.get("traits", {})
	for slot in traits:
		var t: Dictionary = get_trait(str(traits[slot]))
		might += int(t.get("might_mod", 0))
		guard += int(t.get("guard_mod", 0))
	return {"might": might, "guard": guard}


## Every ability granted by a creature's parts (deduped), plus its
## signature "moves" list from creatures.json (the [WIRING] move names
## like gorge/fossil_crush are real abilities in abilities.json).
static func creature_abilities(creature: Dictionary) -> Array:
	ensure_loaded()
	var out: Array = []
	var traits: Dictionary = creature.get("traits", {})
	for slot in traits:
		var t: Dictionary = get_trait(str(traits[slot]))
		for ab in t.get("ability_ids", []):
			if not out.has(ab):
				out.append(ab)
	for mv in creature.get("moves", []):
		var mid := str(mv)
		if _abilities.has(mid) and not out.has(mid):
			out.append(mid)
	return out


## Shop lookup: {name, stock: [{item_id, price}]}. Empty dict when unknown.
static func get_shop(shop_id: String) -> Dictionary:
	ensure_loaded()
	return _shops.get(shop_id, {})
