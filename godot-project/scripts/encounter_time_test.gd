extends SceneTree
## Q4: encounter slow-mo is opt-in and never freezes the game globally.
const Clock := preload("res://scripts/encounter_time.gd")
var failures := 0
var checks := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("[ENCOUNTER TIME] " + description)

func _run() -> void:
	Clock.cancel()
	var global_scale := Engine.time_scale
	_check(is_equal_approx(Clock.scale, 1.0), "encounter clock starts neutral")
	_check(is_equal_approx(Clock.scaled_delta(0.1), 0.1),
		"ambient step matches real time outside an asking")
	Clock.slow_mo(0.10, 0.30)
	_check(is_equal_approx(Clock.scale, 0.3) and
		is_equal_approx(Clock.scaled_delta(0.1), 0.03),
		"encounter-only slow-mo multiplies opted-in actor delta")
	_check(Engine.time_scale == global_scale,
		"slow-mo never touches global time or menu input")
	await create_timer(0.03, true, false, true).timeout
	Clock.slow_mo(0.12, 0.45)
	_check(is_equal_approx(Clock.scale, 0.45),
		"retrigger supersedes previous 0.3 multiplier rather than stacking")
	await create_timer(0.08, true, false, true).timeout
	_check(is_equal_approx(Clock.scale, 0.45),
		"old timer cannot restore a newer encounter slow-mo")
	Clock.cancel()
	_check(is_equal_approx(Clock.scale, 1.0),
		"withdraw/walk-away immediately restores encounter clock")
	Clock.slow_mo(0.03, 0.20)
	await create_timer(0.06, true, false, true).timeout
	_check(is_equal_approx(Clock.scale, 1.0),
		"successful timer restores normal clock after duration")
	Clock.slow_mo(0.05, 0.1)
	Clock.cancel()
	Clock.slow_mo(0.12, 0.6)
	await create_timer(0.075, true, false, true).timeout
	_check(is_equal_approx(Clock.scale, 0.6),
		"cancelled prior callback cannot interrupt new asking")
	Clock.cancel()
	Clock.slow_mo(0.0, 0.3)
	_check(is_equal_approx(Clock.scale, 1.0),
		"zero duration is a no-op, no sticky slowdown")
	Clock.slow_mo(0.03, -5.0)
	_check(is_equal_approx(Clock.scale, 0.05),
		"invalid speed safely clamped above zero")
	Clock.cancel()
	_check(is_equal_approx(Engine.time_scale, global_scale),
		"every encounter path leaves the global game clock untouched")
	if failures == 0:
		print("[ENCOUNTER TIME] PASS %d checks" % checks)
	else:
		push_error("[ENCOUNTER TIME] FAIL %d/%d" % [failures, checks])
	quit(1 if failures > 0 else 0)
