extends Control
## Screen-space mobile HUD. Rendering and touch capture are kept together,
## while the parent CanvasLayer decides when mobile controls are visible.
## Supports independent joystick, scythe, interaction, and pause touches.

@export var joystick_radius: float = 82.0
@export var action_radius: float = 53.0
@export var edge_margin: float = 40.0

const DIM := Color(0.055, 0.068, 0.081, 0.52)
const RIM := Color(0.72, 0.70, 0.67, 0.46)
const GOLD := Color(0.78, 0.58, 0.35, 0.85)
const PALE := Color(0.90, 0.92, 0.86, 0.85)

var _joystick_id: int = -1
var _attack_id: int = -1
var _interact_id: int = -1
var _pause_id: int = -1
var _joystick_vector: Vector2 = Vector2.ZERO
var _held_directions: Dictionary = {
	"move_left": false, "move_right": false,
	"move_up": false, "move_down": false
}

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process_input(true)
	queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()
	elif (what == NOTIFICATION_APPLICATION_PAUSED
			or what == NOTIFICATION_APPLICATION_FOCUS_OUT
			or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT):
		# Android interruptions (notification shade, incoming calls, app switch)
		# can swallow finger-up events. Clear synthetic actions on backgrounding,
		# so returning to play never resumes a stuck walk, swing, or interaction.
		_cancel_gameplay_touches()
		_pause_id = -1
		queue_redraw()

func _radius() -> float:
	return minf(joystick_radius, size.y * 0.145)

func _button_radius() -> float:
	return minf(action_radius, size.y * 0.094)

func _joy_center() -> Vector2:
	var r := _radius()
	return Vector2(edge_margin + r, size.y - edge_margin - r)

func _attack_center() -> Vector2:
	var r := _button_radius()
	return Vector2(size.x - edge_margin - r, size.y - edge_margin - r * 2.15)

func _interact_center() -> Vector2:
	var r := _button_radius()
	return Vector2(size.x - edge_margin - r * 3.4, size.y - edge_margin - r)

## ReserveClockHUD occupies the top-right 16..62px strip (CanvasLayer 11).
## Give the touch menu its own clearance below that display, away from the
## bottom-right attack/use cluster, so the clock cannot obscure its label.
## The room handles a synthetic ui_cancel exactly like Escape.
func _pause_center() -> Vector2:
	return Vector2(size.x - edge_margin - 32.0, edge_margin + 110.0)


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			_begin_touch(touch.index, touch.position)
		else:
			_end_touch(touch.index)
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if drag.index == _joystick_id:
			_set_joystick(drag.position)
			get_viewport().set_input_as_handled()

func _begin_touch(index: int, point: Vector2) -> void:
	if index == _joystick_id or index == _attack_id or index == _interact_id or index == _pause_id:
		return
	if _pause_id < 0 and point.distance_to(_pause_center()) <= 42.0:
		_pause_id = index
		# Never carry held gameplay buttons into a paused scene. This also
		# prevents a finger lifted while paused from leaving a stuck attack.
		_cancel_gameplay_touches()
		_send_action("ui_cancel", true)
		_send_action("ui_cancel", false)
		queue_redraw()
		get_viewport().set_input_as_handled()
	elif _joystick_id < 0 and point.distance_to(_joy_center()) <= _radius() * 1.55:
		_joystick_id = index
		_set_joystick(point)
		get_viewport().set_input_as_handled()
	elif _attack_id < 0 and point.distance_to(_attack_center()) <= _button_radius() * 1.25:
		_attack_id = index
		_send_action("scythe_swing", true)
		queue_redraw()
		get_viewport().set_input_as_handled()
	elif _interact_id < 0 and point.distance_to(_interact_center()) <= _button_radius() * 1.25:
		_interact_id = index
		_send_action("interact", true)
		queue_redraw()
		get_viewport().set_input_as_handled()

func _end_touch(index: int) -> void:
	if index == _pause_id:
		_pause_id = -1
		queue_redraw()
		get_viewport().set_input_as_handled()
	elif index == _joystick_id:
		_joystick_id = -1
		_joystick_vector = Vector2.ZERO
		_apply_movement()
		queue_redraw()
		get_viewport().set_input_as_handled()
	elif index == _attack_id:
		_attack_id = -1
		_send_action("scythe_swing", false)
		queue_redraw()
		get_viewport().set_input_as_handled()
	elif index == _interact_id:
		_interact_id = -1
		_send_action("interact", false)
		queue_redraw()
		get_viewport().set_input_as_handled()

## Explicitly release all action captures before a pause or scene change.
func _cancel_gameplay_touches() -> void:
	_joystick_id = -1
	_joystick_vector = Vector2.ZERO
	_apply_movement()
	if _attack_id >= 0:
		_attack_id = -1
		_send_action("scythe_swing", false)
	if _interact_id >= 0:
		_interact_id = -1
		_send_action("interact", false)
	queue_redraw()


func _set_joystick(point: Vector2) -> void:
	var delta := (point - _joy_center()) / _radius()
	_joystick_vector = delta.limit_length(1.0)
	if _joystick_vector.length() < 0.22:
		_joystick_vector = Vector2.ZERO
	_apply_movement()
	queue_redraw()

func _apply_movement() -> void:
	_set_direction("move_left", _joystick_vector.x < -0.25)
	_set_direction("move_right", _joystick_vector.x > 0.25)
	_set_direction("move_up", _joystick_vector.y < -0.25)
	_set_direction("move_down", _joystick_vector.y > 0.25)

func _set_direction(action: String, pressed: bool) -> void:
	if bool(_held_directions[action]) == pressed:
		return
	_held_directions[action] = pressed
	if pressed:
		Input.action_press(action)
	else:
		Input.action_release(action)

func _send_action(action: String, pressed: bool) -> void:
	# These must reach ReaperPlayer._unhandled_input() rather than simply
	# setting Input.is_action_pressed(). This keeps combo presses distinct.
	var synthetic := InputEventAction.new()
	synthetic.action = action
	synthetic.pressed = pressed
	synthetic.strength = 1.0 if pressed else 0.0
	Input.parse_input_event(synthetic)

func _exit_tree() -> void:
	_cancel_gameplay_touches()
	_pause_id = -1

func _weapon_caption() -> String:
	var gs = get_node_or_null("/root/GameState")
	if gs != null and gs.has_method("get_form") and int(gs.get_form()) == 1:
		return "SWORD"
	return "SCYTHE"

func _process(_delta: float) -> void:
	var current := _weapon_caption()
	if current != _last_caption:
		_last_caption = current
		queue_redraw()

var _last_caption: String = ""

func _draw() -> void:
	var jr := _radius()
	var jc := _joy_center()
	draw_circle(jc, jr + 12.0, DIM)
	draw_arc(jc, jr + 12.0, 0.0, TAU, 60, RIM, 3.0, true)
	draw_circle(jc, jr * 0.74, Color(0.25, 0.30, 0.30, 0.18))
	var knob := jc + _joystick_vector * jr * 0.58
	draw_circle(knob, jr * 0.39, Color(0.54, 0.59, 0.60, 0.61))
	draw_arc(knob, jr * 0.39, 0.0, TAU, 36, PALE, 2.5, true)
	_draw_button(_attack_center(), _button_radius(), _weapon_caption(), _attack_id >= 0)
	_draw_button(_interact_center(), _button_radius(), "USE", _interact_id >= 0)
	_draw_button(_pause_center(), 31.0, "MENU", _pause_id >= 0)

func _draw_button(center: Vector2, radius: float, caption: String, pressed: bool) -> void:
	draw_circle(center, radius + 5.0, Color(0.02, 0.025, 0.03, 0.3))
	draw_circle(center, radius, GOLD.darkened(0.48) if pressed else DIM)
	draw_arc(center, radius, 0.0, TAU, 48, GOLD if pressed else RIM, 3.0, true)
	var font := get_theme_default_font()
	if font != null:
		var font_size := 17
		var start := center + Vector2(-radius + 5.0, float(font_size) * 0.38)
		draw_string(font, start, caption, HORIZONTAL_ALIGNMENT_CENTER, (radius - 5.0) * 2.0, font_size, PALE)
