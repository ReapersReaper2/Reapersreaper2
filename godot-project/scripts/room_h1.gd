extends "res://scripts/room.gd"
## H1 — Town Plaza (Ch2 hub center). Form 3.
##
## NOTE: intentionally no class_name (project convention).
## Trigger "wrath_confront": fires on first plaza visit AFTER the bounty
## board tutorial (flag h1_board_read). Wrath (greybox — his master was
## blocked) confronts Mollosar, then the first rival battle starts.
## He survives either way (spare_on_loss); rivalry flag is set on win
## and on loss.

## Placeholder confrontation lines (story bot replaces with canon).
const WRATH_INTRO_LINES: Array = [
	{"type": "direction", "text": "A reaper in a red-lined robe steps out of the lantern light. His tally board is full. Yours has one mark."},
	{"type": "dialogue", "character": "WRATH", "text": "So. The new reaper finally crawled out of the river."},
	{"type": "dialogue", "character": "MOLLOSAR", "text": "And you are?"},
	{"type": "dialogue", "character": "WRATH", "text": "The one taking the contracts you pass up. Let's see if you can do more than shepherd."},
]

var _wrath_fight_started := false


func _on_room_trigger(trigger_id: String, _trigger: Area2D) -> void:
	if trigger_id == "wrath_confront":
		_maybe_wrath()


func _maybe_wrath() -> void:
	# Requires the board tutorial first; one-shot via the trigger flag
	# (room.gd already set trigger_wrath_confront) plus the rivalry flag.
	if not _flag("h1_board_read"):
		return
	if _flag("wrath_rivalry") or _flag("trainer_wrath_rival_1_defeated"):
		return
	if _wrath_fight_started:
		return
	_wrath_fight_started = true
	if dialogue_box != null and dialogue_box.has_method("start_dialogue"):
		if dialogue_box.has_signal("dialogue_finished"):
			dialogue_box.dialogue_finished.connect(_start_wrath_battle, CONNECT_ONE_SHOT)
		dialogue_box.start_dialogue(WRATH_INTRO_LINES)
	else:
		_start_wrath_battle()


func _start_wrath_battle() -> void:
	var bm = get_node_or_null("/root/BattleManager")
	if bm == null or not bm.has_method("start_trainer_battle"):
		push_warning("room_h1: BattleManager missing, Wrath fight skipped")
		return
	var pos := player.position if player != null else Vector2.ZERO
	print("[ROOM] h1: Wrath rival battle")
	bm.start_trainer_battle("wrath_rival_1", room_id, pos)
