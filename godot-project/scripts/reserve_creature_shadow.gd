extends Node2D
## Soft, ground-anchored contact shadow for an animated living resident.
## top_level is set by the owner so texture scale/lean never distort it.
@export var radius_x: float = 40.0
@export var radius_y: float = 13.0

func _ready() -> void:
	queue_redraw()

func _draw() -> void:
	# Two soft nested ellipses approximate painterly ground contact using
	# inexpensive canvas primitives, without importing extra placeholder art.
	draw_set_transform(Vector2.ZERO, 0.0,
		Vector2(maxf(radius_x, 1.0) / 32.0, maxf(radius_y, 1.0) / 32.0))
	draw_circle(Vector2.ZERO, 32.0, Color(0.025, 0.037, 0.035, 0.22))
	draw_circle(Vector2.ZERO, 20.0, Color(0.018, 0.027, 0.028, 0.23))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
