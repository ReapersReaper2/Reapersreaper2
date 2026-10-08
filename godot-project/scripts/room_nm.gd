extends "res://scripts/room.gd"
## NM — Night Market (late hub, post-Kanryu announcement).
##
## NOTE: intentionally no class_name (project convention).
## Moon-gate from H1 opens after h2_announcement_done. Three vendors:
## Ivy (no haggling — "the price is the price"), the Masked Stall
## (rare goods), and the Toll (two-price: credits + a creature release).
## The roped-off stall is a locked teaser for a future unlock
## (flag hook: nm_stall_unlocked — not functional yet).

const UiText = preload("res://scripts/ui_text.gd")


func _on_room_trigger(trigger_id: String, _trigger: Area2D) -> void:
	if trigger_id == "nm_entry":
		_play_entry_line()


func _play_entry_line() -> void:
	var line := UiText.night_market("entry")
	if line.is_empty():
		return
	if dialogue_box != null and dialogue_box.has_method("start_dialogue"):
		dialogue_box.start_dialogue([
			{"type": "direction", "text": "A moon-gate sighs shut behind you."},
			{"type": "dialogue", "character": "???", "text": line},
		])
