extends Area2D
## Fabricator station interactable — the Grove, room_g1 (Armor Plant Grove).
##
## NOTE: intentionally no class_name (project convention).
## [E] prompt (lore_object.gd pattern). Opens the Living Fabricator UI.
## The mother plant itself stays a negotiation beat (ArmorPlant node);
## this station is the workbench beside it. Pauses the tree while open.

const FabricatorUiScript := preload("res://scripts/fabricator_ui.gd")

@export var prompt_text: String = "[E] use fabricator"

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


func _open() -> void:
	_ui = FabricatorUiScript.new()
	_ui.game_state = get_node_or_null("/root/GameState")
	get_tree().root.add_child(_ui)
	_ui._ready()
	_ui.closed.connect(_on_closed)
	get_tree().paused = true
	_ui.open_fabricator()
	if has_node("Prompt"):
		($Prompt as Label).visible = false
	print("[FABRICATOR] station opened")


func _on_closed() -> void:
	get_tree().paused = false
	if _ui != null and is_instance_valid(_ui):
		_ui.queue_free()
	_ui = null
