extends StaticBody2D
## Individual solid garden tree with its own canvas depth.
## Trunks sort against Mollosar's feet; crowns can obscure him naturally.

const BARK := Color(0.16, 0.13, 0.13)
const BARK_LIGHT := Color(0.29, 0.23, 0.19)
const SHADOW := Color(0.035, 0.055, 0.045, 0.42)
const FOLIAGE := Color(0.095, 0.19, 0.145)
const FOLIAGE_MID := Color(0.145, 0.275, 0.18)
const FOLIAGE_LIGHT := Color(0.23, 0.36, 0.23)

func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	z_as_relative = false
	z_index = clampi(int(round(position.y + 18.0)), -1900, 1900)
	var collider := CollisionShape2D.new()
	var trunk := CircleShape2D.new()
	trunk.radius = 24.0
	collider.shape = trunk
	collider.position = Vector2(0, 18)
	add_child(collider)
	queue_redraw()

func _draw() -> void:
	# The canopy sits ABOVE the trunk, like a real top-down RPG object.
	draw_circle(Vector2(11, 25), 30.0, SHADOW)
	draw_line(Vector2(0, 26), Vector2(0, -34), BARK, 18.0, true)
	draw_line(Vector2(-23, 23), Vector2(0, 13), BARK, 9.0, true)
	draw_line(Vector2(23, 23), Vector2(0, 13), BARK, 9.0, true)
	draw_line(Vector2(-4, 11), Vector2(-4, -31), BARK_LIGHT, 2.0, true)
	draw_circle(Vector2(0, -47), 46.0, FOLIAGE)
	draw_circle(Vector2(-24, -58), 31.0, FOLIAGE_MID)
	draw_circle(Vector2(21, -72), 32.0, FOLIAGE)
	draw_circle(Vector2(-8, -85), 24.0, FOLIAGE_LIGHT)
	draw_circle(Vector2(-28, -64), 9.0, FOLIAGE_LIGHT.darkened(0.20))
