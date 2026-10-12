# scripts/touch_controls.gd
extends CanvasLayer
class_name TouchControls

# Simple first-pass mobile controls for Reaper's Reaper.
# Feeds existing Godot Input actions. Does not touch player movement code.

@export var joystick_radius: float = 90.0
@export var joystick_deadzone: float = 18.0
@export var joystick_position := Vector2(150, -150)
@export var action_button_margin := Vector2(150, 150)

var joystick_touch_id: int = -1
var joystick_center: Vector2
var joystick_vector := Vector2.ZERO

var joystick_base: Control
var joystick_knob: Control
var swing_button: Button
var interact_button: Button

func _ready() -> void:
	if not DisplayServer.is_touchscreen_available():
		visible = false
		return
	_build_controls()
	_place_controls()
	get_viewport().size_changed.connect(_place_controls)
	set_process(true)

func _process(_delta: float) -> void:
	if not visible:
		return
	_update_movement_actions()
	_update_attack_label()

func _build_controls() -> void:
	joystick_base = Panel.new()
	joystick_base.name = "VirtualJoystick"
	joystick_base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	joystick_base.size = Vector2(joystick_radius * 2.0, joystick_radius * 2.0)
	var base_style := StyleBoxFlat.new()
	base_style.bg_color = Color(0.07, 0.10, 0.12, 0.54)
	base_style.border_color = Color(0.69, 0.59, 0.40, 0.82)
	base_style.set_border_width_all(3)
	base_style.set_corner_radius_all(int(joystick_radius))
	(joystick_base as Panel).add_theme_stylebox_override("panel", base_style)
	joystick_knob = Panel.new()
	joystick_knob.name = "Knob"
	joystick_knob.mouse_filter = Control.MOUSE_FILTER_IGNORE
	joystick_knob.size = Vector2(62, 62)
	var knob_style := StyleBoxFlat.new()
	knob_style.bg_color = Color(0.60, 0.69, 0.65, 0.86)
	knob_style.border_color = Color(0.9, 0.83, 0.67, 0.9)
	knob_style.set_border_width_all(2)
	knob_style.set_corner_radius_all(31)
	(joystick_knob as Panel).add_theme_stylebox_override("panel", knob_style)
	joystick_base.add_child(joystick_knob)
	add_child(joystick_base)
	_reset_joystick()

	interact_button = _make_button("INTERACT", "interact")
	interact_button.name = "InteractButton"
	add_child(interact_button)
	swing_button = _make_button("SWORD", "scythe_swing")
	swing_button.name = "ScytheButton"
	add_child(swing_button)


func _make_button(text: String, action: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(148, 148)
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 19)
	button.add_theme_color_override("font_color", Color(0.97, 0.92, 0.80))
	for state in ["normal", "hover", "pressed", "disabled"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.14, 0.17, 0.19, 0.79)
		if state == "pressed":
			style.bg_color = Color(0.41, 0.29, 0.24, 0.96)
		style.border_color = Color(0.75, 0.55, 0.30, 0.93)
		style.set_border_width_all(3)
		style.set_corner_radius_all(74)
		button.add_theme_stylebox_override(state, style)
	button.button_down.connect(func() -> void: _send_button_action(action, true))
	button.button_up.connect(func() -> void: _send_button_action(action, false))
	return button

func _update_attack_label() -> void:
	if swing_button == null:
		return
	var gs = get_node_or_null("/root/GameState")
	if gs == null or not gs.has_method("get_form"):
		return
	swing_button.text = "SWORD" if int(gs.get_form()) == 1 else "SCYTHE"


func _place_controls() -> void:
	if joystick_base == null:
		return
	var viewport_size := get_viewport().get_visible_rect().size
	joystick_base.position = Vector2(72, viewport_size.y - 245)
	interact_button.position = Vector2(viewport_size.x - 390, viewport_size.y - 205)
	swing_button.position = Vector2(viewport_size.x - 205, viewport_size.y - 255)
	joystick_center = joystick_base.position + joystick_base.size * 0.5


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			if joystick_touch_id == -1 and _inside_joystick(event.position):
				joystick_touch_id = event.index
				_update_joystick(event.position)
		else:
			if event.index == joystick_touch_id:
				joystick_touch_id = -1
				joystick_vector = Vector2.ZERO
				_reset_joystick()
	elif event is InputEventScreenDrag:
		if event.index == joystick_touch_id:
			_update_joystick(event.position)

func _inside_joystick(position: Vector2) -> bool:
	return position.distance_to(joystick_center) <= joystick_radius * 1.5

func _update_joystick(position: Vector2) -> void:
	var offset := position - joystick_center
	if offset.length() > joystick_radius:
		offset = offset.normalized() * joystick_radius
	joystick_vector = offset / joystick_radius
	if joystick_vector.length() < joystick_deadzone / joystick_radius:
		joystick_vector = Vector2.ZERO
	joystick_knob.position = (
		joystick_base.size * 0.5 - joystick_knob.size * 0.5 + offset
	)

func _reset_joystick() -> void:
	joystick_knob.position = (
		joystick_base.size * 0.5 - joystick_knob.size * 0.5
	)

func _update_movement_actions() -> void:
	_set_action("move_left", joystick_vector.x < -0.25)
	_set_action("move_right", joystick_vector.x > 0.25)
	_set_action("move_up", joystick_vector.y < -0.25)
	_set_action("move_down", joystick_vector.y > 0.25)

func _set_action(action: String, pressed: bool) -> void:
	if pressed:
		if not Input.is_action_pressed(action):
			Input.action_press(action)
	else:
		if Input.is_action_pressed(action):
			Input.action_release(action)


## Action presses are also sent through the input event pipeline so
## ReaperPlayer._unhandled_input() and other gameplay handlers receive them.
## Input.action_press() alone changes the polling state but does not
## generate an InputEvent for event-driven scythe and interaction code.
func _send_button_action(action: String, pressed: bool) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	event.strength = 1.0 if pressed else 0.0
	Input.parse_input_event(event)
