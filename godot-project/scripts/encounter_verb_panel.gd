extends CanvasLayer
## Screen-space creature asking verbs (ENCOUNTER-IMPL §1.6).
## This component is presentation ONLY: no creature outcome, captured
## creature, fruit inventory, or save write may originate from a button.
## Its consumers decide when to open, which verbs are enabled, and whether
## an OPEN, baited, nearby Lullmother permits the conditional Guide button.
signal verb_chosen(verb: String)

const VERBS := ["Offer", "Tend", "Withdraw"]
const GUIDE_VERB := "Guide"
const INK := Color(0.042, 0.052, 0.072, 0.965)
const EDGE := Color(0.55, 0.44, 0.30, 0.94)

var _frame: PanelContainer = null
var _title: Label = null
var _buttons: HBoxContainer = null
var _guide_available: bool = false
var _actor_name: String = ""
var _is_open: bool = false
var _controls: Dictionary = {}

## At 1280x720: left edge 236 (joystick ends ~216);
## right edge 980 (USE starts ~1002), bottom = 700.
## Never cover the mobile movement or action thumb zones.
static func mobile_verb_rect(viewport_size: Vector2) -> Rect2:
	var scale_factor := minf(viewport_size.x / 1280.0, viewport_size.y / 720.0)
	var left := 236.0 * scale_factor
	var right := 300.0 * scale_factor
	var height := 152.0 * scale_factor
	var bottom := 20.0 * scale_factor
	return Rect2(Vector2(left, viewport_size.y - height - bottom),
		Vector2(maxf(1.0, viewport_size.x - left - right), height))


static func button_target_width(viewport_size: Vector2, count: int) -> float:
	var area := mobile_verb_rect(viewport_size)
	var scale_factor := minf(viewport_size.x / 1280.0, viewport_size.y / 720.0)
	return maxf(1.0, (area.size.x - 36.0 * scale_factor -
		maxi(0, count - 1) * 8.0 * scale_factor) / maxi(1, count))


static func allowed_verbs(can_guide: bool) -> Array[String]:
	var result: Array[String] = []
	result.assign(VERBS)
	if can_guide:
		result.append(GUIDE_VERB)
	return result


func _ready() -> void:
	layer = 9 # above MobileTouch layer 8, below actual modal overlays
	_build()
	_apply_layout()
	visible = false
	if not get_viewport().size_changed.is_connected(_apply_layout):
		get_viewport().size_changed.connect(_apply_layout)


func open_for(actor_name: String, can_guide: bool = false) -> void:
	if _frame == null:
		_build()
	_actor_name = actor_name
	_guide_available = can_guide
	_is_open = true
	_title.text = "THE ASKING    " + _actor_name.to_upper()
	_rebuild_buttons()
	_apply_layout()
	visible = true


func dismiss() -> void:
	_is_open = false
	visible = false
	# Button events already queued by a departing touch must be ignored.
	for button_value in _controls.values():
		(button_value as Button).disabled = true


func is_open() -> bool:
	return _is_open


func has_verb(verb: String) -> bool:
	return _controls.has(verb)


func _on_pressed(verb: String) -> void:
	if _is_open and has_verb(verb):
		verb_chosen.emit(verb)


func _build() -> void:
	if _frame != null:
		return
	_frame = PanelContainer.new()
	_frame.name = "AskingFrame"
	_frame.mouse_filter = Control.MOUSE_FILTER_STOP
	var surround := StyleBoxFlat.new()
	surround.bg_color = INK
	surround.border_color = EDGE
	surround.set_border_width_all(2)
	surround.set_corner_radius_all(10)
	surround.content_margin_left = 18
	surround.content_margin_right = 18
	surround.content_margin_top = 12
	surround.content_margin_bottom = 10
	_frame.add_theme_stylebox_override("panel", surround)
	add_child(_frame)
	var body := VBoxContainer.new()
	body.name = "Body"
	body.add_theme_constant_override("separation", 9)
	_frame.add_child(body)
	_title = Label.new()
	_title.name = "AskingTitle"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 23)
	_title.add_theme_color_override("font_color", Color(0.96, 0.88, 0.70))
	body.add_child(_title)
	_buttons = HBoxContainer.new()
	_buttons.name = "Verbs"
	_buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	_buttons.add_theme_constant_override("separation", 8)
	body.add_child(_buttons)


func _rebuild_buttons() -> void:
	for child in _buttons.get_children():
		_buttons.remove_child(child)
		child.queue_free()
	_controls.clear()
	var options := allowed_verbs(_guide_available)
	for verb in options:
		var button := Button.new()
		button.name = verb
		button.text = verb.to_upper()
		button.focus_mode = Control.FOCUS_ALL
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", 22)
		button.add_theme_color_override("font_color", Color(0.97, 0.93, 0.85))
		button.add_theme_stylebox_override("normal",
			_button_style(Color(0.10, 0.12, 0.15), EDGE))
		button.add_theme_stylebox_override("hover",
			_button_style(Color(0.20, 0.16, 0.14), Color(0.95, 0.76, 0.46)))
		button.add_theme_stylebox_override("pressed",
			_button_style(Color(0.24, 0.19, 0.16), Color(1.0, 0.88, 0.57)))
		button.pressed.connect(_on_pressed.bind(verb))
		_buttons.add_child(button)
		_controls[verb] = button


func _button_style(fill: Color, outline: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = outline
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.content_margin_left = 9
	style.content_margin_right = 9
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	return style


func _apply_layout() -> void:
	if _frame == null or not is_inside_tree():
		return
	var size := get_viewport().get_visible_rect().size
	var r := mobile_verb_rect(size)
	_frame.position = r.position
	_frame.size = r.size
	var options := allowed_verbs(_guide_available)
	var button_width := button_target_width(size, options.size())
	var scale_factor := minf(size.x / 1280.0, size.y / 720.0)
	for button_value in _controls.values():
		var button: Button = button_value
		button.custom_minimum_size = Vector2(button_width, 60.0 * scale_factor)
