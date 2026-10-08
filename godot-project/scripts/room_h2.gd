extends "res://scripts/room.gd"
## H2 — Murray's Bar (interior). Form 3.
##
## NOTE: intentionally no class_name (project convention).
## Trigger "kanryu_announce": on first entry, the blue butterfly-winged
## messenger fairy (greybox orb visual, spawned by this script) delivers
## the Soul Council's Kanryu bounty announcement — P1-scaled terms:
## 50,000 Soul Credits + one vault item (restricted list). One-shot.

## Placeholder announcement lines (story bot replaces with canon).
const ANNOUNCE_LINES: Array = [
	{"type": "direction", "text": "A blue butterfly-winged messenger fairy spirals down from the rafters, scattering cold light over the bar."},
	{"type": "dialogue", "character": "MESSENGER", "text": "Hear the Soul Council's bounty, spoken once."},
	{"type": "dialogue", "character": "MESSENGER", "text": "KANRYU. Fifty thousand Soul Credits. One vault item, from the restricted list."},
	{"type": "dialogue", "character": "MESSENGER", "text": "This mark does not expire. It does not negotiate. It waits."},
	{"type": "direction", "text": "The fairy dissolves into blue motes. Murray doesn't look up from his glass."},
	{"type": "dialogue", "character": "MURRAY", "text": "…You heard the lady."},
]

var _messenger = null


func _on_room_trigger(trigger_id: String, trigger: Area2D) -> void:
	if trigger_id == "kanryu_announce":
		_play_announcement(trigger)


func _play_announcement(trigger: Area2D) -> void:
	_spawn_messenger(trigger.position + Vector2(0, -120))
	if dialogue_box != null and dialogue_box.has_method("start_dialogue"):
		if dialogue_box.has_signal("dialogue_finished"):
			dialogue_box.dialogue_finished.connect(_dismiss_messenger, CONNECT_ONE_SHOT)
		dialogue_box.start_dialogue(ANNOUNCE_LINES)
	_set_flag("h2_announcement_done")
	print("[ROOM] h2: Kanryu bounty announced")


## Greybox messenger fairy: blue orb with butterfly wings (Luna-like).
func _spawn_messenger(pos: Vector2) -> void:
	if _messenger != null:
		return
	_messenger = Node2D.new()
	_messenger.name = "MessengerFairy"
	_messenger.position = pos
	_messenger.z_index = 10
	var glow := Polygon2D.new()
	glow.color = Color(0.3, 0.5, 1.0, 0.22)
	glow.polygon = PackedVector2Array([
		Vector2(26, 0), Vector2(24, 10), Vector2(18.4, 18.4), Vector2(10, 24),
		Vector2(0, 26), Vector2(-10, 24), Vector2(-18.4, 18.4), Vector2(-24, 10),
		Vector2(-26, 0), Vector2(-24, -10), Vector2(-18.4, -18.4), Vector2(-10, -24),
		Vector2(0, -26), Vector2(10, -24), Vector2(18.4, -18.4), Vector2(24, -10),
	])
	_messenger.add_child(glow)
	for side in [-1, 1]:
		var wing := Polygon2D.new()
		wing.position = Vector2(7 * side, -3)
		wing.color = Color(0.4, 0.6, 1.0, 0.9)
		wing.polygon = PackedVector2Array([
			Vector2(0, 0), Vector2(16 * side, -14), Vector2(13 * side, 10),
		])
		_messenger.add_child(wing)
	var orb := Polygon2D.new()
	orb.color = Color(0.5, 0.7, 1.0, 1.0)
	orb.polygon = PackedVector2Array([
		Vector2(10, 0), Vector2(9.2, 3.8), Vector2(7.1, 7.1), Vector2(3.8, 9.2),
		Vector2(0, 10), Vector2(-3.8, 9.2), Vector2(-7.1, 7.1), Vector2(-9.2, 3.8),
		Vector2(-10, 0), Vector2(-9.2, -3.8), Vector2(-7.1, -7.1), Vector2(-3.8, -9.2),
		Vector2(0, -10), Vector2(3.8, -9.2), Vector2(7.1, -7.1), Vector2(9.2, -3.8),
	])
	_messenger.add_child(orb)
	add_child(_messenger)


func _dismiss_messenger() -> void:
	if _messenger != null and is_instance_valid(_messenger):
		_messenger.queue_free()
	_messenger = null
