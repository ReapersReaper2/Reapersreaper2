extends Area2D
## Dice table interactable — Murray's Bar back room (room_h2).
##
## NOTE: intentionally no class_name (project convention).
## [E] prompt (lore_object.gd pattern). Opens the Dead Man's Dice UI.
## Gated on m2_hub_unlocked. Pauses the tree while the table is open.

const DiceUiScript := preload("res://scripts/dice_ui.gd")

@export var prompt_text: String = "[E] Dead Man's Dice"
@export var locked_hint: String = "[WIRING] The back room is closed for now."

var _player_in_range := false
var _ui = null


func _ready() -> void:
	if has_node("Prompt"):
		($Prompt as Label).text = prompt_text
		($Prompt as Label).visible = false
	if not is_inside_tree():
		return
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	if not body_exited.is_connected(_on_body_exited):
		body_exited.connect(_on_body_exited)


func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	_player_in_range = true
	if has_node("Prompt"):
		($Prompt as Label).visible = true


func _on_body_exited(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	_player_in_range = false
	if has_node("Prompt"):
		($Prompt as Label).visible = false


func _unhandled_input(event: InputEvent) -> void:
	if not _player_in_range or _ui_open():
		return
	if event.is_action_pressed("interact"):
		get_viewport().set_input_as_handled()
		_open.call_deferred()


func _ui_open() -> bool:
	return _ui != null and is_instance_valid(_ui) and _ui.is_open()


func _gs():
	return get_node_or_null("/root/GameState")


func _open() -> void:
	var gs = _gs()
	if gs != null and gs.has_method("get_flag") and not bool(gs.get_flag("m2_hub_unlocked")):
		_say(locked_hint)
		return
	_ui = DiceUiScript.new()
	_ui.game_state = gs
	get_tree().root.add_child(_ui)
	_ui._ready()
	_ui.closed.connect(_on_closed)
	get_tree().paused = true
	_ui.open_table()
	if has_node("Prompt"):
		($Prompt as Label).visible = false
	print("[DICE] table opened")


func _on_closed() -> void:
	get_tree().paused = false
	if _ui != null and is_instance_valid(_ui):
		_ui.queue_free()
	_ui = null


func _say(text: String) -> void:
	var box = get_tree().get_first_node_in_group("dialogue_box")
	if box != null and box.has_method("start_dialogue"):
		box.start_dialogue([{"type": "direction", "text": text}])
	else:
		print("[DICE] ", text)
