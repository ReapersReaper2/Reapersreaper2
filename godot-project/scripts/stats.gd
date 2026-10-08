extends Node
## Gameplay stat tracker for Reaper's Reaper (feeds Achievements).
##
## NOTE: intentionally no class_name (project convention — see save_system.gd).
## Registered as the "Stats" autoload; game code calls Stats.record_kill()
## etc. directly on the singleton.
##
## Stats live in-memory here and are mirrored into GameState state["stats"]
## on every mutation, so saves capture them automatically (see
## save_system.gd default_save). Under headless -s harnesses the autoloads
## aren't loaded — inject game_state / achievements manually, same pattern
## as save_test.gd.

# Untyped on purpose: autoloads or injected (headless tests).
var game_state = null
var achievements = null

## Canonical fresh stats. save_system.gd default_save() builds from this
## (via preload) so the save schema and the live tracker can't drift.
static func default_stats() -> Dictionary:
	return {
		"reap_kills": 0,
		"souls_guided": 0,
		"damage_taken_p1": 0,
		"max_combo_hits": 0,
		"rooms_entered": [],
		"creatures_caught": 0,
	}

## Room ids that count toward the "explorer" achievement (M1).
const EXPLORER_ROOMS: Array[String] = ["p1", "p3", "c1"]

var _stats: Dictionary = {}


func _ready() -> void:
	if game_state == null:
		game_state = get_node_or_null("/root/GameState")
	if achievements == null:
		achievements = get_node_or_null("/root/Achievements")
	if game_state != null and game_state.has_signal("state_loaded"):
		if not game_state.state_loaded.is_connected(_pull):
			game_state.state_loaded.connect(_pull)
	_pull()


## An invader (or dummy) died to the scythe.
func record_kill() -> void:
	_stats["reap_kills"] = int(_stats.get("reap_kills", 0)) + 1
	var kills: int = int(_stats["reap_kills"])
	_ach("first_reap", kills >= 1)
	_ach("invader_slayer_25", kills >= 25)
	_ach("invader_slayer_100", kills >= 100)
	_push()


## A creature was caught (soul snare). Fires the "catcher" milestone.
func record_catch() -> void:
	_stats["creatures_caught"] = int(_stats.get("creatures_caught", 0)) + 1
	var caught: int = int(_stats["creatures_caught"])
	_ach("first_catch", caught >= 1)
	_ach("catch_10", caught >= 10)
	_push()


## A wisp was guided home (guide-touch release).
func record_guide() -> void:
	_stats["souls_guided"] = int(_stats.get("souls_guided", 0)) + 1
	var guided: int = int(_stats.get("souls_guided"))
	_ach("bounty_done", guided >= 1)
	_ach("wisp_guide_10", guided >= 10)
	_push()


## The player took damage. Currently only P1 combat deals damage, so this
## feeds damage_taken_p1 (generalize when later chapters add damage).
func record_damage(amount: int) -> void:
	_stats["damage_taken_p1"] = int(_stats.get("damage_taken_p1", 0)) + maxi(0, amount)
	_push()


## The player entered a room (room.gd calls this on _ready).
func record_room(room_id: String) -> void:
	var rooms: Array = _stats.get("rooms_entered", [])
	if not rooms.has(room_id):
		rooms.append(room_id)
	_stats["rooms_entered"] = rooms
	var all_found := true
	for want in EXPLORER_ROOMS:
		if not rooms.has(want):
			all_found = false
			break
	_ach("explorer", all_found)
	_push()


## The scythe landed N hits across one combo (swing1 + swing2).
## full_combo unlocks at 2: at least one hit in each swing.
func record_combo_hits(hits: int) -> void:
	_stats["max_combo_hits"] = maxi(int(_stats.get("max_combo_hits", 0)), hits)
	_ach("full_combo", int(_stats["max_combo_hits"]) >= 2)
	_push()


## Called by the P1 wave spawner when the final wave clears.
func on_waves_cleared() -> void:
	_ach("bridge_cleared", true)
	_ach("deathless_p1", int(_stats.get("damage_taken_p1", 0)) == 0)
	_push()


## Read access for UI/debug.
func get_stats() -> Dictionary:
	return _stats


## Debug helper: zero everything (also clears the GameState mirror).
func reset_all() -> void:
	_stats = default_stats()
	_push()


func _ach(id: String, condition: bool) -> void:
	if condition and achievements != null and achievements.has_method("unlock"):
		achievements.unlock(id)


## Pull the live stats from GameState (or start from defaults).
func _pull() -> void:
	_stats = default_stats()
	var gs = _game_state_dict()
	if gs != null:
		var saved: Dictionary = gs.get("stats", {})
		for key in _stats.keys():
			if saved.has(key):
				_stats[key] = saved[key]


## Mirror the live stats into GameState so saves capture them.
func _push() -> void:
	var gs = _game_state_dict()
	if gs != null:
		gs["stats"] = _stats.duplicate(true)


func _game_state_dict():
	if game_state != null and game_state.get("state") is Dictionary:
		return game_state.get("state")
	return null
