extends RefCounted
## Trainer data layer: loads data/trainers.json once and exposes lookups.
## No class_name / autoload on purpose: consumers preload this script, so it
## works in headless -s test scripts too (same pattern as creature_data.gd).

const PATH := "res://data/trainers.json"

static var _data: Dictionary = {}
static var _loaded := false


static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	if not FileAccess.file_exists(PATH):
		push_warning("trainer_data: missing " + PATH)
		return
	var text := FileAccess.get_file_as_string(PATH)
	var parsed = JSON.parse_string(text)
	if parsed is Dictionary:
		_data = parsed
	else:
		push_warning("trainer_data: failed to parse " + PATH)


## Full trainer dict, or {} when unknown. Keys: name, roster
## ([{creature_id, level}, ...]), reward_credits, pre_dialogue, post_dialogue.
static func get_trainer(trainer_id: String) -> Dictionary:
	ensure_loaded()
	var all: Dictionary = _data.get("trainers", {})
	var t = all.get(trainer_id, {})
	return t if t is Dictionary else {}


## GameState flag marking this trainer defeated (one-time battles).
static func defeat_flag(trainer_id: String) -> String:
	return "trainer_" + trainer_id + "_defeated"
