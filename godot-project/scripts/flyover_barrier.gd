extends StaticBody2D
## FlyoverBarrier — a low obstacle (thorn wall, gap, rubble) that blocks
## the walking player but is ignored while flying.
##
## Setup: collision_layer = 8 (layer 4), collision_mask = 0.
## The player toggles its own mask between Flight.WALK_MASK (9) and
## Flight.FLY_MASK (1); see scripts/flight.gd for the convention.
##
## NOTE: intentionally no class_name (project convention).

@export var tint: Color = Color(0.35, 0.25, 0.2, 1)


func _ready() -> void:
	collision_layer = 8
	collision_mask = 0
	if has_node("Visual"):
		($Visual as Polygon2D).color = tint
