extends Area2D
## VineExchange — post-game mourning vine cutting exchange (Grimley/Ivy).
##
## NOTE: intentionally no class_name (project convention).
## Delivery point for the cutting exchange. The player takes a cutting
## from one garden (via a lore_object give_item) and delivers it to the
## other garden. No quest marker — the reactions are the reward.
##
## Exports:
##   required_item: item_id the player must hold (e.g. "ivy_cutting")
##   reaction_lines: dialogue played on delivery
##   speaker: character name for the dialogue box
##   done_flag: GameState flag set after delivery (one-shot)
##   lock_flag: GameState flag that must be true (post-game gate)

@export var required_item: String = ""
@export var reaction_lines: PackedStringArray = PackedStringArray()
@export var speaker: String = "???"
@export var done_flag: String = ""
@export var lock_flag: String = "e2_fragment_planted"
@export var prompt_text: String = "[E] offer cutting"
@export var locked_hint: String = "[WIRING] Not yet."
@export var missing_hint: String = "[WIRING] You have no cutting to offer."

var _player_in_range := false
var _dialogue_open := false


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	if has_node("Prompt"):
		($Prompt as Label).text = prompt_text


func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		_player_in_range = true
		_update_prompt()


func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		_player_in_range = false
		if has_node("Prompt"):
			($Prompt as Label).visible = false


func _update_prompt() -> void:
	if not has_node("Prompt"):
		return
	var gs = get_node_or_null("/root/GameState")
	if done_flag != "" and gs != null and gs.has_method("get_flag") and bool(gs.get_flag(done_flag)):
		($Prompt as Label).visible = false
		return
	($Prompt as Label).visible = _player_in_range and not _dialogue_open


func _unhandled_input(event: InputEvent) -> void:
	if _dialogue_open or not _player_in_range:
		return
	if event.is_action_pressed("interact"):
		_activate()
		get_viewport().set_input_as_handled()


func _activate() -> void:
	var gs = get_node_or_null("/root/GameState")
	# Post-game gate.
	if lock_flag != "" and (gs == null or not gs.has_method("get_flag") or not bool(gs.get_flag(lock_flag))):
		_say_hint(locked_hint)
		return
	# Already delivered.
	if done_flag != "" and gs != null and gs.has_method("get_flag") and bool(gs.get_flag(done_flag)):
		return
	# Need the cutting.
	if required_item == "" or gs == null or not gs.has_method("get_item_count"):
		return
	if int(gs.get_item_count(required_item)) <= 0:
		_say_hint(missing_hint)
		return
	# Consume and react.
	if gs.has_method("use_item"):
		gs.use_item(required_item)
	if done_flag != "" and gs.has_method("set_flag"):
		gs.set_flag(done_flag)
	_say_reaction()


func _say_hint(text: String) -> void:
	var box = get_tree().get_first_node_in_group("dialogue_box")
	if box == null or not box.has_method("start_dialogue"):
		return
	_dialogue_open = true
	if has_node("Prompt"):
		($Prompt as Label).visible = false
	box.start_dialogue([{"type": "dialogue", "character": speaker, "text": text}])
	_connect_finished(box)


func _say_reaction() -> void:
	var box = get_tree().get_first_node_in_group("dialogue_box")
	if box == null or not box.has_method("start_dialogue"):
		return
	_dialogue_open = true
	if has_node("Prompt"):
		($Prompt as Label).visible = false
	var entries: Array = []
	for line in reaction_lines:
		entries.append({"type": "dialogue", "character": speaker, "text": line})
	box.start_dialogue(entries)
	_connect_finished(box)


func _connect_finished(box: Node) -> void:
	if box.has_signal("dialogue_finished") and not box.dialogue_finished.is_connected(_on_dialogue_finished):
		box.dialogue_finished.connect(_on_dialogue_finished)


func _on_dialogue_finished() -> void:
	if not _dialogue_open:
		return
	_dialogue_open = false
	_update_prompt()
