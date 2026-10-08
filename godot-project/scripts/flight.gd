extends RefCounted
## Flight — Form 9 (Winged Ascended) flight mode queries.
##
## Flight is available when Depower.flight_available() is true: the U3
## wings beat set form9_unlocked + ch13_repowered (depower state NONE).
##
## Collision convention (top-down, no gravity):
## - Fly-over barriers (thorn walls, gaps, low obstacles) live on
##   collision layer 4 (FLY_LAYER = 8). They are StaticBody2D nodes
##   using scripts/flyover_barrier.gd.
## - Walking player: collision_mask = WALK_MASK (1 | 8) — blocked by
##   walls AND fly-over barriers.
## - Flying player: collision_mask = FLY_MASK (1) — passes over
##   fly-over barriers, still blocked by full walls.
##
## NOTE: intentionally no class_name (project convention). Use via
## `const Flight = preload("res://scripts/flight.gd")`.

const Depower := preload("res://scripts/depower.gd")

## Collision layer value for fly-over barriers (layer 4).
const FLY_LAYER := 8
## Player mask while walking: walls (1) + fly-over barriers (8).
const WALK_MASK := 9
## Player mask while flying: walls only — fly-over barriers ignored.
const FLY_MASK := 1
## Flight move-speed multiplier (applied to walk_speed).
const SPEED_MULT := 1.4
## Visual altitude cue: how far up the Visuals node lifts while flying.
const LIFT_PX := 14.0


## Flight is unlocked: full repower (depower NONE) + form9 flag.
static func can_fly(gs) -> bool:
	return Depower.flight_available(gs)


## Why the player can't fly right now ("" when they can).
static func locked_hint(gs) -> String:
	if can_fly(gs):
		return ""
	if Depower.state(gs) != Depower.State.NONE:
		return "Your wings are dead weight while depowered."
	return "You don't have wings yet. (Form 9 unlocks at the Usurper Tree.)"


## Flight speed multiplier.
static func speed_mult() -> float:
	return SPEED_MULT
