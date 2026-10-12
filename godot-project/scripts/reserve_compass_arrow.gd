extends Control
## Compact non-interactive HUD direction marker for garden exploration.
## Up on screen means target is north of Mollosar; never rotates the camera.
## Pure canvas drawing — no new fonts, textures, animation imports or input.

const OUTER := Color(0.58, 0.57, 0.49, 0.84)
const INNER := Color(0.10, 0.14, 0.16, 0.95)
const ARROW := Color(0.98, 0.80, 0.48, 1.0)
const EDGE := Color(0.99, 0.94, 0.77, 0.92)

var _bearing: Vector2 = Vector2.UP
var _active: bool = false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(31.0, 31.0)
	queue_redraw()

func point_to(direction: Vector2) -> void:
	var new_bearing := direction.normalized() if direction.length_squared() > 0.001 else Vector2.UP
	if _bearing.distance_squared_to(new_bearing) < 0.0001 and _active:
		return
	_bearing = new_bearing
	_active = true
	queue_redraw()

func clear() -> void:
	if not _active:
		return
	_active = false
	queue_redraw()

func is_active() -> bool:
	return _active

func direction() -> Vector2:
	return _bearing

func _draw() -> void:
	if not _active:
		return
	var center := size * 0.5
	draw_circle(center, 15.2, INNER)
	draw_arc(center, 14.6, 0.0, TAU, 32, OUTER, 1.5, true)
	# Arrow geometry is authored pointing UP. World Y and screen Y have
	# the same sign, so we rotate UP toward the target's direction.
	var angle := _bearing.angle() + PI * 0.5
	draw_set_transform(center, angle, Vector2.ONE)
	draw_colored_polygon(PackedVector2Array([
		Vector2(0, -12), Vector2(8, 9), Vector2(0, 5), Vector2(-8, 9)
	]), ARROW)
	draw_polyline(PackedVector2Array([
		Vector2(-8, 9), Vector2(0, -12), Vector2(8, 9)
	]), EDGE, 1.4, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
