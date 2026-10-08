extends RefCounted
## Bounty contract system for Reaper's Reaper (the core gameplay loop).
##
## NOTE: intentionally no class_name (project convention).
## Static manager; game code passes the GameState node in (same pattern as
## WeaponData.unlock). Contract state lives in state["contracts"]:
##   {"accepted": [ids], "turned_in": [ids], "progress": {"reap:wispwillow": n}}
## plus GameState flags contract_<id>_accepted / contract_<id>_done, so the
## journal and board can also read status through plain flags.
##
## Objective types (see data/contracts.json):
##   reap    — defeat the creature in a WILD battle (trainers don't count)
##   catch   — catch the creature ("any" matches every species)
##   collect — pick up the item
##   flag    — a GameState flag is set
##
## The Kanryu bounty is NOT a contract: it lives in bounty_board.json,
## sealed, and can never be accepted.

const CONTRACTS_PATH := "res://data/contracts.json"

static var _cache: Array = []


static func load_contracts() -> Array:
	if not _cache.is_empty():
		return _cache
	if not FileAccess.file_exists(CONTRACTS_PATH):
		return []
	var f := FileAccess.open(CONTRACTS_PATH, FileAccess.READ)
	if f == null:
		return []
	var d = JSON.parse_string(f.get_as_text())
	if d is Dictionary:
		_cache = d.get("contracts", [])
	return _cache


static func get_contract(contract_id: String) -> Dictionary:
	for c in load_contracts():
		if str(c.get("id", "")) == contract_id:
			return c
	return {}


static func contract_ids() -> Array:
	var out: Array = []
	for c in load_contracts():
		out.append(str(c.get("id", "")))
	return out


## The contracts block inside the save payload (lazy: old saves work).
static func _data(gs) -> Dictionary:
	if gs == null or gs.get("state") == null:
		return {"accepted": [], "turned_in": [], "progress": {}}
	var st: Dictionary = gs.get("state")
	if not st.has("contracts") or not (st["contracts"] is Dictionary):
		st["contracts"] = {"accepted": [], "turned_in": [], "progress": {}}
	return st["contracts"]


static func accepted_ids(gs) -> Array:
	return (_data(gs).get("accepted", []) as Array).duplicate()


static func turned_in_ids(gs) -> Array:
	return (_data(gs).get("turned_in", []) as Array).duplicate()


static func is_accepted(gs, contract_id: String) -> bool:
	return _data(gs).get("accepted", []).has(contract_id)


static func is_turned_in(gs, contract_id: String) -> bool:
	return _data(gs).get("turned_in", []).has(contract_id)


## Status for UI: "done" (turned in) | "ready" (objectives met) |
## "accepted" | "available" | "locked" (prereq unmet).
static func status(gs, contract_id: String) -> String:
	var c := get_contract(contract_id)
	if c.is_empty():
		return "locked"
	if is_turned_in(gs, contract_id):
		return "done"
	if not is_accepted(gs, contract_id):
		return "available" if can_accept(gs, contract_id) else "locked"
	return "ready" if is_complete(gs, contract_id) else "accepted"


static func can_accept(gs, contract_id: String) -> bool:
	var c := get_contract(contract_id)
	if c.is_empty():
		return false
	if is_accepted(gs, contract_id) or is_turned_in(gs, contract_id):
		return false
	if bool(c.get("repeatable", false)) == false and is_turned_in(gs, contract_id):
		return false
	var req_flag: String = str(c.get("required_flag", ""))
	if req_flag != "" and not _flag(gs, req_flag):
		return false
	var req_c: String = str(c.get("required_contract", ""))
	if req_c != "" and not is_turned_in(gs, req_c):
		return false
	return true


## Take a contract from the board. Returns false when prereqs fail,
## the id is unknown/sealed, or it's already accepted or done.
static func accept(gs, contract_id: String) -> bool:
	if not can_accept(gs, contract_id):
		return false
	var d := _data(gs)
	(d.get("accepted", []) as Array).append(contract_id)
	_set_flag(gs, "contract_" + contract_id + "_accepted")
	return true


## Per-objective progress: {text, current, target, done}.
static func objective_progress(gs, objective: Dictionary) -> Dictionary:
	var otype: String = str(objective.get("type", "flag"))
	var text: String = str(objective.get("text", ""))
	if otype == "flag":
		var done := _flag(gs, str(objective.get("flag", "")))
		return {"text": text, "current": 1 if done else 0, "target": 1, "done": done}
	var key := _progress_key(objective)
	var target := maxi(1, int(objective.get("target", 1)))
	var current := int((_data(gs).get("progress", {}) as Dictionary).get(key, 0))
	return {"text": text, "current": mini(current, target), "target": target, "done": current >= target}


static func objectives_progress(gs, contract_id: String) -> Array:
	var out: Array = []
	var c := get_contract(contract_id)
	for o in c.get("objectives", []):
		out.append(objective_progress(gs, o))
	return out


static func is_complete(gs, contract_id: String) -> bool:
	var c := get_contract(contract_id)
	if c.is_empty() or not is_accepted(gs, contract_id):
		return false
	if is_turned_in(gs, contract_id):
		return false
	for o in c.get("objectives", []):
		if not bool(objective_progress(gs, o).get("done", false)):
			return false
	return true


## Turn in a completed contract at the board. Pays Soul Credits + items,
## marks it done, unlocks the Contractor achievement on first turn-in.
## Returns {ok, credits, items} — ok is false when not ready.
static func turn_in(gs, contract_id: String) -> Dictionary:
	var result := {"ok": false, "credits": 0, "items": {}}
	if not is_complete(gs, contract_id):
		return result
	var c := get_contract(contract_id)
	var credits := int(c.get("reward_credits", 0))
	var items: Dictionary = c.get("reward_items", {})
	if gs != null:
		if credits > 0 and gs.has_method("add_soul_credits"):
			gs.add_soul_credits(credits)
		for item_id in items:
			if gs.has_method("add_item"):
				gs.add_item(str(item_id), int(items[item_id]))
	var d := _data(gs)
	if not (d.get("turned_in", []) as Array).has(contract_id):
		(d.get("turned_in", []) as Array).append(contract_id)
	_set_flag(gs, "contract_" + contract_id + "_done")
	_unlock(gs, "contractor")
	result["ok"] = true
	result["credits"] = credits
	result["items"] = items
	return result


## Generic progress tick. Keys look like "reap:wispwillow".
static func add_progress(gs, key: String, n: int = 1) -> void:
	if n <= 0:
		return
	var d := _data(gs)
	var prog: Dictionary = d.get("progress", {})
	prog[key] = int(prog.get(key, 0)) + n


static func record_reap(gs, creature_id: String) -> void:
	add_progress(gs, "reap:" + str(creature_id))


static func record_catch(gs, creature_id: String) -> void:
	add_progress(gs, "catch:" + str(creature_id))
	add_progress(gs, "catch:any")


static func record_collect(gs, item_id: String) -> void:
	add_progress(gs, "collect:" + str(item_id))


static func _progress_key(objective: Dictionary) -> String:
	var otype: String = str(objective.get("type", ""))
	match otype:
		"reap":
			return "reap:" + str(objective.get("creature", ""))
		"catch":
			return "catch:" + str(objective.get("creature", ""))
		"collect":
			return "collect:" + str(objective.get("item", ""))
	return ""


static func _flag(gs, flag: String) -> bool:
	if gs != null and gs.has_method("get_flag"):
		return bool(gs.get_flag(flag))
	return false


static func _set_flag(gs, flag: String) -> void:
	if gs != null and gs.has_method("set_flag"):
		gs.set_flag(flag)


## Null-safe achievement unlock through the GameState's achievements ref.
static func _unlock(gs, achievement_id: String) -> void:
	if gs == null:
		return
	var ach = gs.get("achievements")
	if ach != null and ach.has_method("unlock"):
		ach.unlock(achievement_id)
