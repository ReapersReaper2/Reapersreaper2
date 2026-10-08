extends RefCounted
## Combat-scoped hitstop clock.
##
## While a hitstop is active, CombatTime.scale reads 0.0 and combat nodes
## (swing timers, knockback, spawn logic) multiply their delta by it, so the
## impact frame hangs. UI and dialogue run on unscaled delta and are
## unaffected — unlike Engine.time_scale, which would freeze everything.
##
## No class_name / autoload on purpose: consumers preload this script, so it
## works in headless -s test scripts too (autoloads don't load there).
##   const CombatTime = preload("res://scripts/combat_time.gd")

## Current combat time multiplier: 1.0 normally, 0.0 during hitstop.
static var scale: float = 1.0
## Debug/test hook: increments every time a hitstop fires.
static var hitstop_count: int = 0
static var _token: int = 0


## Freeze combat for `duration` seconds of real time. Re-triggering while a
## hitstop is already active extends it instead of stacking restores.
static func hitstop(duration: float) -> void:
	_token += 1
	var mine: int = _token
	scale = 0.0
	hitstop_count += 1
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		scale = 1.0
		return
	await tree.create_timer(duration, true, false, true).timeout
	if mine == _token:
		scale = 1.0
