extends Area2D
## KeyDoor — a locked door opened by the fabricator's living key.
##
## NOTE: intentionally no class_name (project convention).
## [E] prompt (lore_object.gd pattern). When the player carries a
## "living_key", [E] consumes it and sets `flag` (unlocking the door for
## good). Otherwise shows the locked hint. All text [WIRING] wiring-written,
## flagged for story-bot revision.

@export var flag: String = "f2_supply_unlocked"
@export var locked_hint: String = "[WIRING] Locked tight. Something grown — not forged — could open this."
@export var unlock_lines: PackedStringArray = PackedStringArray([
	"[WIRING] The living key unfolds into the lock like it was always the shape of it.",
	"[WIRING] The door swings open. Inside: quiet, dust, and things worth taking later."])

var _player_in_range := false
var _dialogue_open := false


func _ready() -> void:
	if has_node("Prompt"):
		($Prompt as Label).visible = false
	_update_prompt()
	if not is_inside_tree():
		return
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	if not body_exited.is_connected(_on_body_exited):
		body_exited.connect(_on_body_exited)
	var box = get_tree().get_first_node_in_group("dialogue_box")
	if box != null and box.has_signal("dialogue_finished"):
		if not box.dialogue_finished.is_connected(_on_dialogue_finished):
			box.dialogue_finished.connect(_on_dialogue_finished)


func _gs():
	return get_node_or_null("/root/GameState")


func _is_open() -> bool:
	var gs = _gs()
	return gs != null and gs.has_method("get_flag") and bool(gs.get_flag(flag))


func _has_key() -> bool:
	var gs = _gs()
	return gs != null and gs.has_method("get_item_count") and int(gs.get_item_count("living_key")) > 0


func _update_prompt() -> void:
	if not has_node("Prompt"):
		return
	if _is_open():
		($Prompt as Label).text = "[E] supply room"
	elif _has_key():
		($Prompt as Label).text = "[E] unlock (living key)"
	else:
		($Prompt as Label).text = "[E] inspect"


func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	_player_in_range = true
	_update_prompt()
	if has_node("Prompt"):
		($Prompt as Label).visible = true


func _on_body_exited(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	_player_in_range = false
	if has_node("Prompt"):
		($Prompt as Label).visible = false


func _unhandled_input(event: InputEvent) -> void:
	if _dialogue_open or not _player_in_range:
		return
	if event.is_action_pressed("interact"):
		get_viewport().set_input_as_handled()
		_activate.call_deferred()


func _activate() -> void:
	var gs = _gs()
	if _is_open():
		_say("[WIRING] The supply room. Smithy overflow — take what you need. (Stock hook: story bot.)")
		return
	if _has_key() and gs != null:
		gs.use_item("living_key")
		gs.set_flag(flag, true)
		_say_lines(unlock_lines)
		_update_prompt()
		return
	_say(locked_hint)


func _say(text: String) -> void:
	var box = get_tree().get_first_node_in_group("dialogue_box")
	if box != null and box.has_method("start_dialogue"):
		_dialogue_open = true
		box.start_dialogue([{"type": "direction", "text": text}])
	else:
		print("[DOOR] ", text)


func _say_lines(lines: PackedStringArray) -> void:
	var box = get_tree().get_first_node_in_group("dialogue_box")
	if box == null or not box.has_method("start_dialogue"):
		_say(str("\n".join(lines)))
		return
	_dialogue_open = true
	var entries: Array = []
	for line in lines:
		entries.append({"type": "dialogue", "character": "DOOR", "text": line})
	box.start_dialogue(entries)
	if has_node("Prompt"):
		($Prompt as Label).visible = false


func _on_dialogue_finished() -> void:
	_dialogue_open = false
