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
	set_process(true)

func _process(_delta: float) -> void:
	if not visible:
		return
	_update_movement_actions()

func _build_controls() -> void:
	joystick_base = Control.new()
	joystick_base.name = "VirtualJoystick"
	joystick_base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	joystick_base.size = Vector2(joystick_radius * 2.0, joystick_radius * 2.0)

	var base_panel := ColorRect.new()
	base_panel.color = Color(1, 1, 1, 0.15)
	base_panel.size = joystick_base.size
	base_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	joystick_base.add_child(base_panel)

	joystick_knob = Control.new()
	joystick_knob.name = "Knob"
	joystick_knob.mouse_filter = Control.MOUSE_FILTER_IGNORE
	joystick_knob.size = Vector2(50, 50)
	joystick_knob.position = joystick_base.size * 0.5 - joystick_knob.size * 0.5

	var knob_panel := ColorRect.new()
	knob_panel.color = Color(1, 1, 1, 0.35)
	knob_panel.size = joystick_knob.size
	knob_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	joystick_knob.add_child(knob_panel)
	joystick_base.add_child(joystick_knob)
	add_child(joystick_base)

	interact_button = _make_button("Interact", "interact")
	interact_button.name = "InteractButton"
	add_child(interact_button)

	swing_button = _make_button("Scythe", "scythe_swing")
	swing_button.name = "ScytheButton"
	add_child(swing_button)

func _make_button(text: String, action: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(130, 130)
	button.focus_mode = Control.FOCUS_NONE
	button.button_down.connect(func() -> void: Input.action_press(action))
	button.button_up.connect(func() -> void: Input.action_release(action))
	return button

func _place_controls() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	joystick_base.position = Vector2(
		100,
		viewport_size.y - 220
	)
	interact_button.position = Vector2(
		viewport_size.x - 280,
		viewport_size.y - 220
	)
	swing_button.position = Vector2(
		viewport_size.x - 140,
		viewport_size.y - 300
	)
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
