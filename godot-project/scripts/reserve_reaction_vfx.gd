extends Node2D
## Small world-space visual acknowledgement for an observed Reserve resident.
## VFX only: no battle damage, no bonding flags, no collision.
@export var lifetime: float = 0.9

const GOLD := Color(0.94, 0.76, 0.48)
const MOON := Color(0.69, 0.77, 0.82)
var _age: float = 0.0

func _ready() -> void:
	z_as_relative = false
	z_index = clampi(int(round(global_position.y)) + 50, -1850, 1850)

func _process(delta: float) -> void:
	_age += maxf(0.0, delta)
	if _age >= lifetime:
		queue_free()
		return
	queue_redraw()

func _draw() -> void:
	if lifetime <= 0.0:
		return
	var t := clampf(_age / lifetime, 0.0, 1.0)
	var alpha := (1.0 - t) * (1.0 - t)
	var wave := GOLD
	wave.a = 0.76 * alpha
	# Golden soul-thread ripples expand across the ground.
	draw_set_transform(Vector2(0, 16), 0.0, Vector2(1, 0.36))
	draw_arc(Vector2.ZERO, 12.0 + t * 78.0, 0.0, TAU, 32, wave, 3.0, true)
	if t > 0.22:
		var secondary := MOON
		secondary.a = alpha * 0.50
		draw_arc(Vector2.ZERO, 8.0 + (t - 0.22) * 67.0, 0.0, TAU, 24, secondary, 2.0, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# Three firefly motes float up from a willing observation.
	for i in range(3):
		var phase := float(i) * 2.094
		var p := Vector2(sin(phase + t * 2.0) * (17.0 + t * 19.0),
			-10.0 - t * (42.0 + float(i * 11)))
		var mote := MOON if i == 1 else GOLD
		mote.a = alpha
		draw_circle(p, 3.8 * (1.0 - t * 0.50), mote)
