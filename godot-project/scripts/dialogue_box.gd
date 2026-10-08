extends CanvasLayer
class_name DialogueBox
## Bottom-anchored dialogue UI: typewriter text, name label, portrait
## placeholder, choice buttons. Feed it parsed entries from DialogueParser.
##
## Flow: start_dialogue(entries, index) -> entries play in order.
## - dialogue/direction/conditional: shown as text, advance on interact.
## - trigger: fires `trigger_fired` and auto-continues (never displayed).
## - choice: shows buttons, waits for a pick, fires `choice_made`.
## Emits `dialogue_finished` when the list is exhausted.

signal dialogue_finished
signal trigger_fired(trigger_text: String)
signal choice_made(option: Dictionary)

## Characters per second for the typewriter effect.
@export var chars_per_second: float = 45.0

var _entries: Array = []
var _index: int = 0
var _typing: bool = false
var _char_progress: float = 0.0
var _full_text: String = ""
var _active: bool = false

@onready var _panel: PanelContainer = $Panel
@onready var _name_label: Label = $Panel/Margin/VBox/NameLabel
@onready var _portrait_label: Label = $Panel/Margin/VBox/HBox/Portrait/InitialLabel
@onready var _text_label: RichTextLabel = $Panel/Margin/VBox/HBox/TextLabel
@onready var _hint_label: Label = $Panel/Margin/VBox/HintLabel
@onready var _choice_box: VBoxContainer = $Panel/Margin/VBox/ChoiceBox


func _ready() -> void:
	visible = false
	_text_label.visible_characters = -1


func _process(delta: float) -> void:
	if not _active or not _typing:
		return
	_char_progress += chars_per_second * delta
	var shown := int(_char_progress)
	if shown >= _full_text.length():
		_text_label.visible_characters = -1
		_typing = false
	else:
		_text_label.visible_characters = shown


func _unhandled_input(event: InputEvent) -> void:
	if not _active:
		return
	if event.is_action_pressed("interact") or event.is_action_pressed("scythe_swing"):
		advance()
		get_viewport().set_input_as_handled()


## Begin playing entries from start_index.
func start_dialogue(entries: Array, start_index: int = 0) -> void:
	_entries = entries
	_index = start_index
	_active = true
	visible = true
	_show_current()


func advance() -> void:
	if not _active:
		return
	if _typing:
		# Complete the line instantly on first press.
		_text_label.visible_characters = -1
		_typing = false
		return
	var e: Dictionary = _entries[_index]
	if e.get("type") == "choice":
		return  # must pick a button
	_index += 1
	_show_current()


func _show_current() -> void:
	_clear_choices()
	if _index >= _entries.size():
		_finish()
		return
	var e: Dictionary = _entries[_index]
	match e.get("type"):
		"trigger":
			trigger_fired.emit(e.get("text", ""))
			_index += 1
			_show_current()
		"choice":
			_show_choice(e)
		"dialogue":
			_show_text(e.get("character", ""), e.get("text", ""), false)
		"direction", "conditional":
			_show_text("", e.get("text", ""), true)
		"scene_heading":
			# Headings are structural; skip silently in the box.
			_index += 1
			_show_current()
		_:
			_index += 1
			_show_current()


func _show_text(speaker: String, text: String, dim: bool) -> void:
	_name_label.text = speaker
	_name_label.visible = not speaker.is_empty()
	_portrait_label.text = speaker.left(1) if not speaker.is_empty() else "?"
	_full_text = text
	_char_progress = 0.0
	_typing = true
	_text_label.visible_characters = 0
	_text_label.text = text
	# Dim style for stage directions / conditional notes.
	_text_label.modulate = Color(0.65, 0.65, 0.72) if dim else Color.WHITE
	_name_label.modulate = Color(0.65, 0.65, 0.72) if dim else Color.WHITE
	_hint_label.text = "[E] continue"


func _show_choice(e: Dictionary) -> void:
	_name_label.text = "Choose"
	_name_label.visible = true
	_name_label.modulate = Color(1.0, 0.85, 0.45)
	_portrait_label.text = "?"
	_text_label.modulate = Color.WHITE
	_full_text = ""
	_typing = false
	_text_label.visible_characters = -1
	_text_label.text = "What does Mollosar do?"
	_hint_label.text = "Pick one."
	var options: Array = e.get("options", [])
	for opt in options:
		var b := Button.new()
		var label := "(%s) %s" % [opt.get("key", "?"), opt.get("text", "")]
		var tags: Array = opt.get("tags", [])
		if not tags.is_empty():
			label += "   [" + ", ".join(tags) + "]"
		b.text = label
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var captured: Dictionary = opt
		b.pressed.connect(func() -> void: _pick(captured))
		_choice_box.add_child(b)
	if _choice_box.get_child_count() > 0:
		_choice_box.get_child(0).grab_focus()


func _pick(option: Dictionary) -> void:
	choice_made.emit(option)
	_clear_choices()
	_index += 1
	_show_current()


func _clear_choices() -> void:
	for c in _choice_box.get_children():
		c.queue_free()


## Immediately close the box (used by the cutscene player on skip).
## Emits dialogue_finished so listeners stay consistent.
func force_close() -> void:
	if not _active:
		return
	_clear_choices()
	_finish()


func _finish() -> void:
	_active = false
	visible = false
	dialogue_finished.emit()
