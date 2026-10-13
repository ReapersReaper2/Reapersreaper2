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

const CriticalSpriteLoader := preload("res://scripts/critical_sprite_loader.gd")

signal dialogue_finished
signal trigger_fired(trigger_text: String)
signal choice_made(option: Dictionary)

## Characters per second for the typewriter effect.
@export var chars_per_second: float = 45.0
## Native landscape Android gameplay is flanked by a joystick on the left
## and SWORD/USE on the right. The dialogue sits in the CLEAR CENTER lane.
@export var force_mobile_layout: bool = false

var _entries: Array = []
var _index: int = 0
var _typing: bool = false
var _char_progress: float = 0.0
var _full_text: String = ""
var _active: bool = false
var _portrait_image: TextureRect = null
var _portrait_holder: ColorRect = null

@onready var _panel: PanelContainer = $Panel
@onready var _name_label: Label = $Panel/Margin/VBox/NameLabel
@onready var _portrait_label: Label = $Panel/Margin/VBox/HBox/Portrait/InitialLabel
@onready var _text_label: RichTextLabel = $Panel/Margin/VBox/HBox/TextLabel
@onready var _hint_label: Label = $Panel/Margin/VBox/HintLabel
@onready var _choice_box: VBoxContainer = $Panel/Margin/VBox/ChoiceBox


func _ready() -> void:
	visible = false
	_text_label.visible_characters = -1
	_portrait_holder = $Panel/Margin/VBox/HBox/Portrait as ColorRect
	_portrait_holder.clip_contents = true
	_portrait_image = TextureRect.new()
	_portrait_image.name = "RealPortrait"
	_portrait_image.set_anchors_preset(Control.PRESET_FULL_RECT)
	_portrait_image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_portrait_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_portrait_holder.add_child(_portrait_image)
	# A few older headless harnesses call _ready on a scene that was
	# never added to the tree. No viewport exists in that isolated case.
	if is_inside_tree() and get_viewport() != null:
		_apply_responsive_layout()
		if not get_viewport().size_changed.is_connected(_apply_responsive_layout):
			get_viewport().size_changed.connect(_apply_responsive_layout)


## Rect is computed in viewport units, so it works with Android aspect
## correction as well as a desktop editor preview set to 1280x720.
## For the default 1280x720 HUD: joystick + rim ends at x≈216;
## USE button + rim begins at x≈1002. The dialogue uses x236..980.
static func mobile_dialogue_rect(viewport_size: Vector2) -> Rect2:
	var scale_factor := minf(viewport_size.x / 1280.0, viewport_size.y / 720.0)
	var left_clear := 236.0 * scale_factor
	var right_clear := 300.0 * scale_factor
	var floor_margin := 20.0 * scale_factor
	var height := 178.0 * scale_factor
	return Rect2(Vector2(left_clear, viewport_size.y - height - floor_margin),
		Vector2(maxf(1.0, viewport_size.x - left_clear - right_clear), height))


func _uses_mobile_dialogue() -> bool:
	return force_mobile_layout or OS.has_feature("android") or OS.has_feature("ios") \
		or OS.has_feature("mobile") or DisplayServer.is_touchscreen_available() \
		or bool(ProjectSettings.get_setting("reaper/force_touch_controls", false))


func _apply_responsive_layout() -> void:
	if not _uses_mobile_dialogue():
		return # Keep the wider cinematic panel on keyboard/desktop.
	var rect := mobile_dialogue_rect(get_viewport().get_visible_rect().size)
	_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_panel.position = rect.position
	_panel.size = rect.size
	# Fonts have to read on an actual phone, not only in a headless test.
	_text_label.add_theme_font_size_override("normal_font_size", 24)
	_name_label.add_theme_font_size_override("font_size", 23)
	_hint_label.add_theme_font_size_override("font_size", 17)
	_portrait_holder.custom_minimum_size = Vector2(58, 58)
	var content = get_node_or_null("Panel/Margin/VBox/HBox")
	if content is HBoxContainer:
		(content as HBoxContainer).add_theme_constant_override("separation", 10)


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


## A second NPC/trigger must never overwrite the conversation already
## on screen. Story and cutscene signals belong to the first dialogue.
func is_active() -> bool:
	return _active


## Begin playing entries from start_index. Return false when the screen is
## already occupied (call sites can retry when their own interaction ends).
func start_dialogue(entries: Array, start_index: int = 0) -> bool:
	if _active or entries.is_empty():
		return false
	_entries = entries
	_index = clampi(start_index, 0, entries.size() - 1)
	_active = true
	visible = true
	_show_current()
	return true


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


func _update_portrait(speaker: String) -> void:
	if _portrait_holder == null or _portrait_image == null:
		return
	_portrait_holder.visible = not speaker.is_empty()
	_portrait_image.visible = false
	_portrait_label.visible = true
	var path := ""
	var crop := Rect2()
	match speaker.to_upper():
		"MIRA":
			path = "res://assets/npc/mira.png"
			crop = Rect2(245, 0, 520, 520)
		"SOLDIER":
			path = "res://assets/npc/wounded_soldier.png"
			crop = Rect2(210, 0, 580, 580)
		"MOLLOSAR":
			path = "res://sprites/mollosar/form1_walk_down_spec384.png"
			crop = Rect2(112, 0, 165, 170)
	if path == "":
		return
	var texture := CriticalSpriteLoader.load_texture(path)
	if texture == null:
		return
	var portrait := AtlasTexture.new()
	portrait.atlas = texture
	portrait.region = crop
	_portrait_image.texture = portrait
	_portrait_image.visible = true
	_portrait_label.visible = false


func _show_text(speaker: String, text: String, dim: bool) -> void:
	_name_label.text = speaker
	_name_label.visible = not speaker.is_empty()
	_portrait_label.text = speaker.left(1) if not speaker.is_empty() else "?"
	_update_portrait(speaker)
	_full_text = text
	_char_progress = 0.0
	_typing = true
	_text_label.visible_characters = 0
	_text_label.text = text
	# Dim style for stage directions / conditional notes.
	_text_label.modulate = Color(0.65, 0.65, 0.72) if dim else Color.WHITE
	_name_label.modulate = Color(0.65, 0.65, 0.72) if dim else Color.WHITE
	_hint_label.text = "USE / SWORD to continue" if (OS.has_feature("android") or OS.has_feature("ios") or DisplayServer.is_touchscreen_available()) else "[E / SPACE] continue"


func _show_choice(e: Dictionary) -> void:
	_name_label.text = "Choose"
	_name_label.visible = true
	_name_label.modulate = Color(1.0, 0.85, 0.45)
	_portrait_label.text = "?"
	_update_portrait("Choose")
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
