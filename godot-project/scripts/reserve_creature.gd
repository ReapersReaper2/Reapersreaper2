extends Sprite2D
## ReserveCreature — ambient plant-creature resident of the nursery reserve.
##
## Attach to a Sprite2D in a room scene. On _ready it records its rest Y and
## then runs a gentle sine bob on position.y — no AI, no collision, it just
## BE THERE, visible, with the real art (SPRINT 2026-10-11, Jenn plays today).
##
## NOTE: intentionally no class_name (project convention).

## Bob amplitude in pixels (vertical wobble range around the rest position).
@export var bob_amp: float = 8.0
## Bob speed in radians per second.
@export var bob_speed: float = 1.6

var _base_y: float = 0.0
var _phase: float = 0.0


func _ready() -> void:
	_base_y = position.y
	# Stagger each creature so they don't bob in lockstep.
	_phase = randf() * TAU


func _process(delta: float) -> void:
	_phase += delta * bob_speed
	position.y = _base_y + sin(_phase) * bob_amp
