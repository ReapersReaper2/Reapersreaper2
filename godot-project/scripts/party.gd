extends RefCounted
## Party system for Reaper's Reaper tactical battles.
##
## A party is up to 6 creature instances persisted in GameState.state["party"].
## Each entry is a plain JSON-safe Dictionary:
##   {creature_id, level, xp, current_hp, nickname, ability_ids}
## nickname is stored only (no naming UI yet — that's a later task).
##
## XP curve (TUNING PLACEHOLDER, not canon): xp_to_next = round(20 * level^1.5).
## On level-up, max HP is recomputed via BattleUnit and current HP rises by
## the max-HP delta; a member at 0 HP stays down until healed. Abilities are
## fixed per creature data — nothing is learned on level-up (later task).
##
## No class_name / autoload on purpose: consumers preload this script, so it
## works in headless -s test scripts too (autoloads don't load there).
##   const Party = preload("res://scripts/party.gd")
##
## Mutable state lives in GameState and is passed in as `gs` — the module
## itself holds no mutable state (same pattern as weapon_data.gd).

const CreatureData = preload("res://scripts/creature_data.gd")
const BattleUnit = preload("res://scripts/battle_unit.gd")

const MAX_SIZE := 6
const XP_BASE := 20.0  # tuning placeholder: xp_to_next = round(XP_BASE * level^1.5)
const STARTER_ID := "snapling"
const STARTER_LEVEL := 5


## XP needed to go from `level` to `level + 1`.
static func xp_to_next(level: int) -> int:
	return int(round(XP_BASE * pow(float(maxi(1, level)), 1.5)))


## The raw party array in GameState (created empty when the key is missing).
static func _party(gs: Node) -> Array:
	if not gs.state.has("party"):
		gs.state["party"] = []
	return gs.state["party"]


## Unlock "Full House" when the party hits 6. Best-effort: gs may be a
## test double without a tree, so resolve Achievements defensively.
static func _maybe_full_house(gs: Node) -> void:
	if _party(gs).size() < MAX_SIZE:
		return
	var ach = null
	if gs.has_method("get_node"):
		ach = gs.get_node_or_null("/root/Achievements")
	if ach != null and ach.has_method("unlock"):
		ach.unlock("party_full")


static func size(gs: Node) -> int:
	return _party(gs).size()


static func is_valid_index(gs: Node, index: int) -> bool:
	return index >= 0 and index < _party(gs).size()


## Entry at `index` (the live Dictionary — mutations persist). {} when invalid.
## (Named get_entry, not get: Object.get is native and can't be shadowed.)
static func get_entry(gs: Node, index: int) -> Dictionary:
	if not is_valid_index(gs, index):
		return {}
	return _party(gs)[index]


## Fresh-game party: just the starter.
static func new_game_party(gs: Node) -> void:
	gs.state["party"] = []
	add_creature(gs, STARTER_ID, STARTER_LEVEL)


## A brand-new party entry for the save migration (v1 -> v2).
static func make_starter_entry() -> Dictionary:
	return _make_entry(STARTER_ID, STARTER_LEVEL)


## Public entry factory: build a fresh party-shaped entry without inserting
## it anywhere. Used by storage deposits and battle catches that go straight
## to the vault.
static func make_entry(creature_id: String, level: int) -> Dictionary:
	return _make_entry(creature_id, level)


static func _make_entry(creature_id: String, level: int) -> Dictionary:
	CreatureData.ensure_loaded()
	var c: Dictionary = CreatureData.get_creature(creature_id)
	var lv := maxi(1, level)
	var unit = BattleUnit.new(creature_id, lv)  # max HP only; entry owns runtime HP
	# Sex is assigned at creation (used by the breeding gate). Legacy
	# entries without it get one assigned on first breeding check.
	var _sex := "M" if randf() < 0.5 else "F"
	return {
		"creature_id": creature_id,
		"level": lv,
		"xp": 0,
		"current_hp": unit.max_hp,
		"nickname": "",
		"sex": _sex,
		"ability_ids": CreatureData.creature_abilities(c),
		"statuses": [],
	}


## Add a creature at full HP. False (warning, no write) when the party is
## full or the id is unknown, so a typo can't poison a save.
static func add_creature(gs: Node, creature_id: String, level: int) -> bool:
	CreatureData.ensure_loaded()
	if CreatureData.get_creature(creature_id).is_empty():
		push_warning("Party: refusing unknown creature '%s'" % creature_id)
		return false
	var p: Array = _party(gs)
	if p.size() >= MAX_SIZE:
		push_warning("Party: full (%d), cannot add '%s'" % [MAX_SIZE, creature_id])
		return false
	p.append(_make_entry(creature_id, level))
	_maybe_full_house(gs)
	return true


## Insert a ready-made entry dict (deposit flows, UI placement). Duplicates
## the dict so callers keep ownership. False when full or invalid.
static func append_entry(gs: Node, entry: Dictionary) -> bool:
	var p: Array = _party(gs)
	if p.size() >= MAX_SIZE or entry.is_empty():
		return false
	p.append(entry.duplicate())
	_maybe_full_house(gs)
	return true


static func insert_entry(gs: Node, index: int, entry: Dictionary) -> bool:
	var p: Array = _party(gs)
	if p.size() >= MAX_SIZE or entry.is_empty():
		return false
	if index < 0 or index > p.size():
		return false
	p.insert(index, entry.duplicate())
	return true


static func remove_creature(gs: Node, index: int) -> bool:
	if not is_valid_index(gs, index):
		return false
	_party(gs).remove_at(index)
	return true


static func swap(gs: Node, a: int, b: int) -> bool:
	if not is_valid_index(gs, a) or not is_valid_index(gs, b):
		return false
	var p: Array = _party(gs)
	var tmp: Dictionary = p[a]
	p[a] = p[b]
	p[b] = tmp
	return true


## Max HP for a party entry at its current level.
static func max_hp_for(entry: Dictionary) -> int:
	var unit = BattleUnit.new(str(entry.get("creature_id", "")), int(entry.get("level", 1)))
	return unit.max_hp


## Write runtime HP back to an entry (clamped). Used after battles.
static func set_hp(gs: Node, index: int, hp: int) -> bool:
	var e := get_entry(gs, index)
	if e.is_empty():
		return false
	e["current_hp"] = clampi(hp, 0, max_hp_for(e))
	return true


static func heal_all(gs: Node) -> void:
	for e in _party(gs):
		(e as Dictionary)["current_hp"] = max_hp_for(e)


## Index of the first conscious member, or -1 when the whole party is down.
static func lead_index(gs: Node) -> int:
	var p: Array = _party(gs)
	for i in p.size():
		if int((p[i] as Dictionary).get("current_hp", 0)) > 0:
			return i
	return -1


## Battle-ready lead: {index, creature_id, level, current_hp}, or {} when
## nobody can fight. A fainted lead is never sent out — the next conscious
## member steps up.
static func lead_for_battle(gs: Node) -> Dictionary:
	var i := lead_index(gs)
	if i < 0:
		return {}
	var e: Dictionary = _party(gs)[i]
	return {
		"index": i,
		"creature_id": str(e.get("creature_id", "")),
		"level": int(e.get("level", 1)),
		"current_hp": int(e.get("current_hp", 0)),
	}


## Grant XP to one member. Returns the Array of new levels reached (empty on
## no level-up; several entries on a big gain). Level-ups recompute max HP
## via BattleUnit and lift current HP by the delta — a member at 0 HP stays
## down until healed.
static func gain_xp(gs: Node, index: int, amount: int) -> Array:
	var e := get_entry(gs, index)
	var ups: Array = []
	if e.is_empty() or amount <= 0:
		return ups

	e["xp"] = int(e.get("xp", 0)) + amount
	while int(e["xp"]) >= xp_to_next(int(e["level"])):
		var old_max := max_hp_for(e)
		e["xp"] = int(e["xp"]) - xp_to_next(int(e["level"]))
		e["level"] = int(e["level"]) + 1
		var new_max := max_hp_for(e)
		if int(e["current_hp"]) > 0:
			e["current_hp"] = mini(new_max, int(e["current_hp"]) + (new_max - old_max))
		ups.append(int(e["level"]))
		print("[PARTY] %s grew to Lv%d!" % [str(e.get("creature_id")), int(e["level"])])
	return ups



## --- Out-of-battle care -----------------------------------------------------
## Statuses persist on the entry under "statuses" (Array of String ids).
## Entries from older saves without the key are tolerated (treated healthy).
## Battles sync the battler's statuses back via _sync_party_hp in battle.gd.


## Status ids currently on the member. [] when invalid or none.
static func get_statuses(gs: Node, index: int) -> Array:
	var e := get_entry(gs, index)
	if e.is_empty():
		return []
	return ((e.get("statuses", []) as Array).duplicate())


## Overwrite the member's statuses (deduped, blanks dropped). False when invalid.
static func set_statuses(gs: Node, index: int, statuses: Array) -> bool:
	var e := get_entry(gs, index)
	if e.is_empty():
		return false
	var clean: Array = []
	for sid in statuses:
		var s := str(sid)
		if s != "" and not clean.has(s):
			clean.append(s)
	e["statuses"] = clean
	return true


## Add one status. False when invalid or already present.
static func add_status(gs: Node, index: int, sid: String) -> bool:
	var e := get_entry(gs, index)
	if e.is_empty() or sid == "":
		return false
	var cur := get_statuses(gs, index)
	if cur.has(sid):
		return false
	cur.append(sid)
	e["statuses"] = cur
	return true


## Remove any of `ids` present. Returns how many were cured.
static func cure_statuses(gs: Node, index: int, ids: Array) -> int:
	var e := get_entry(gs, index)
	if e.is_empty():
		return 0
	var cur := get_statuses(gs, index)
	var n := 0
	for sid in ids:
		var s := str(sid)
		if cur.has(s):
			cur.erase(s)
			n += 1
	e["statuses"] = cur
	return n


## Heal `amount` HP on a conscious member (clamped, no overheal).
## Fainted members can't be healed this way — returns the HP actually restored.
static func heal(gs: Node, index: int, amount: int) -> int:
	var e := get_entry(gs, index)
	if e.is_empty():
		return 0
	var cur := int(e.get("current_hp", 0))
	if cur <= 0:
		return 0
	var maxhp := max_hp_for(e)
	var healed := mini(amount, maxhp - cur)
	e["current_hp"] = cur + healed
	return healed


## Revive a fainted member at `fraction` of max HP. False when not fainted.
static func revive(gs: Node, index: int, fraction: float) -> bool:
	var e := get_entry(gs, index)
	if e.is_empty():
		return false
	if int(e.get("current_hp", 0)) > 0:
		return false
	e["current_hp"] = maxi(1, int(round(float(max_hp_for(e)) * fraction)))
	return true