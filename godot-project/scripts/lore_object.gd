extends Area2D
## LoreObject — M3 generic interactable (greybox).
##
## NOTE: intentionally no class_name (project convention).
## One script covers: lore objects, pickups, locked doors, proximity
## triggers, and choice stubs. Visuals are code-drawn Polygon2D children
## in the room .tscn; this script handles prompt + dialogue + flags +
## item/credit rewards. All dialogue is wiring-written [WIRING] and
## flagged for story-bot revision.
##
## Standard children expected: "Range" (CollisionShape2D), "Prompt" (Label),
## "Visual" (Polygon2D, optional — tinted by `tint` if present).

@export var label_text: String = ""
@export var tint: Color = Color(0.7, 0.7, 0.75)
@export var prompt_text: String = "[E] inspect"
@export var lines: PackedStringArray = PackedStringArray()
@export var repeat_lines: PackedStringArray = PackedStringArray()
## Primary flag set on first activation (also used as the one-shot key).
@export var flag: String = ""
## Additional flags set alongside `flag`.
@export var extra_flags: PackedStringArray = PackedStringArray()
## If set and the flag is false, activation is blocked with locked_hint.
@export var lock_flag: String = ""
@export var locked_hint: String = "It doesn't respond."
## Rewards on first activation.
@export var give_item: String = ""
@export var give_credits: int = 0
## If true, fires once ever (tracked by `flag`); otherwise repeats.
@export var one_shot: bool = true

## Emitted on every activation (boss triggers, etc.). Boss fight
## controllers connect to this to start their fights.
signal activated(obj)

## Boss controllers poll this to start the fight after intro dialogue.
func is_dialogue_open() -> bool:
	return _dialogue_open
## If true, fires on body_entered instead of [E] (no prompt shown).
@export var trigger_mode: bool = false

var _player_in_range := false
var _dialogue_open := false


func _ready() -> void:
	if has_node("Visual"):
		($Visual as Polygon2D).color = tint
	if has_node("Prompt"):
		($Prompt as Label).text = prompt_text
		($Prompt as Label).visible = false
	if has_node("Name"):
		($Name as Label).text = label_text
	if not is_inside_tree():
		return  # headless -s: tree services unavailable until inside tree
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	if not body_exited.is_connected(_on_body_exited):
		body_exited.connect(_on_body_exited)
	var box = get_tree().get_first_node_in_group("dialogue_box")
	if box != null and box.has_signal("dialogue_finished"):
		if not box.dialogue_finished.is_connected(_on_dialogue_finished):
			box.dialogue_finished.connect(_on_dialogue_finished)


func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	_player_in_range = true
	if trigger_mode:
		_activate.call_deferred()
	elif has_node("Prompt"):
		($Prompt as Label).visible = true


func _on_body_exited(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	_player_in_range = false
	if has_node("Prompt"):
		($Prompt as Label).visible = false


func _unhandled_input(event: InputEvent) -> void:
	if trigger_mode or _dialogue_open or not _player_in_range:
		return
	if event.is_action_pressed("interact"):
		get_viewport().set_input_as_handled()
		_activate.call_deferred()


func _gs():
	return get_node_or_null("/root/GameState")


func _activate() -> void:
	var gs = _gs()
	# Lock check.
	if lock_flag != "" and (gs == null or not gs.has_method("get_flag") or not bool(gs.get_flag(lock_flag))):
		_say(locked_hint)
		return
	activated.emit(self)
	# One-shot check.
	if one_shot and flag != "" and gs != null and gs.has_method("get_flag") and bool(gs.get_flag(flag)):
		if not repeat_lines.is_empty():
			_say_lines(repeat_lines)
		return
	var use_lines := lines
	if flag != "" and gs != null and gs.has_method("get_flag") and bool(gs.get_flag(flag)):
		if not repeat_lines.is_empty():
			use_lines = repeat_lines
	_say_lines(use_lines)


func _say_lines(use_lines: PackedStringArray) -> void:
	if use_lines.is_empty():
		_grant()
		return
	var box = get_tree().get_first_node_in_group("dialogue_box")
	if box == null or not box.has_method("start_dialogue"):
		push_warning("lore_object.gd: no dialogue box")
		_grant()
		return
	_dialogue_open = true
	if has_node("Prompt"):
		($Prompt as Label).visible = false
	var who := label_text if label_text != "" else "???"
	var entries: Array = []
	for line in use_lines:
		entries.append({"type": "dialogue", "character": who, "text": line})
	box.start_dialogue(entries)


func _say(text: String) -> void:
	var box = get_tree().get_first_node_in_group("dialogue_box")
	if box != null and box.has_method("start_dialogue"):
		_dialogue_open = true
		box.start_dialogue([{"type": "direction", "text": text}])
	else:
		print("[LORE] ", text)


func _on_dialogue_finished() -> void:
	if not _dialogue_open:
		return
	_dialogue_open = false
	_grant()


func _grant() -> void:
	var gs = _gs()
	if gs == null:
		return
	if flag != "" and gs.has_method("set_flag"):
		gs.set_flag(flag, true)
	for f in extra_flags:
		if gs.has_method("set_flag"):
			gs.set_flag(str(f), true)
	if give_item != "" and gs.has_method("add_item"):
		gs.add_item(give_item, 1)
	if give_credits != 0 and gs.has_method("add_soul_credits"):
		gs.add_soul_credits(give_credits)
	print("[LORE] granted flag=", flag, " item=", give_item, " credits=", give_credits)
