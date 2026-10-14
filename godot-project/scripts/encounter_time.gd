extends RefCounted
## Scoped clock for a future Creature EncounterDirector (BOT-002 ruling Q4).
## Unlike Engine.time_scale, this NEVER affects UI, input, animation,
## player movement, or ReserveClock's day/dusk counter. Only the encounter
## actor updates that explicitly opt into scaled_delta() slow down.
## No autoload/class_name; one director owns the call site.
static var scale: float = 1.0
static var _token: int = 0

static func scaled_delta(delta: float) -> float:
	return maxf(0.0, delta) * scale


## Initiate/restart the encounter-only slow-mo. A repeated request cancels
## the older restore timer (token) rather than stacking two multipliers.
## All duration and scale values are proposed tuning inputs, not canon.
static func slow_mo(duration: float = 2.0, factor: float = 0.3) -> void:
	if duration <= 0.0:
		return
	_token += 1
	var mine := _token
	scale = clampf(factor, 0.05, 1.0)
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		scale = 1.0
		return
	await tree.create_timer(duration, true, false, true).timeout
	if mine == _token:
		scale = 1.0


## Called when walking away, changing rooms, or ending the asking.
## Invalidate every pending timer; old callbacks may not change a future
## encounter's scoped time state.
static func cancel() -> void:
	_token += 1
	scale = 1.0
