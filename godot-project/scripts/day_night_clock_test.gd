extends SceneTree
## BOT-001 2026-10-13: 12-minute continuously queryable day/night phase contract.
## godot --headless --path godot-project --script res://scripts/day_night_clock_test.gd
const Clock := preload("res://scripts/reserve_clock.gd")

var checks: int = 0
var failed: int = 0
var starts: Array[String] = []
var ends: Array[String] = []
var dusks: Array[int] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var clock = Clock.new()
	clock.show_clock = true
	clock.apply_world_tint = false
	root.add_child(clock)
	clock.phase_started.connect(_on_started)
	clock.phase_ended.connect(_on_ended)
	clock.dusk_started.connect(_on_dusk)
	check(is_equal_approx(Clock.PROPOSED_CYCLE_SECONDS, 720.0), "full cycle is 12 real minutes")
	check(is_equal_approx(clock.phase_duration_seconds("dawn"), 60.0), "dawn = 1 real minute")
	check(is_equal_approx(clock.phase_duration_seconds("day"), 360.0), "day = 6 real minutes")
	check(is_equal_approx(clock.phase_duration_seconds("dusk"), 120.0), "dusk = 2 real minutes")
	check(is_equal_approx(clock.phase_duration_seconds("night"), 180.0), "night = 3 real minutes")

	clock.set_total_minutes(300.0) # The existing HUD's 05:00 dawn.
	starts.clear()
	ends.clear()
	dusks.clear()
	check(clock.get_phase() == "dawn", "05:00 is dawn")
	check(is_equal_approx(clock.get_phase_remaining_seconds(), 60.0),
		"at dawn start, 60 real seconds remain")
	check(clock._clock_label != null and
		clock._clock_label.text.contains("DAY 1  ·  05:00") and
		clock._clock_label.text.contains("DAWN  ·  01:00 LEFT"),
		"visible HUD displays day, in-world clock and current phase countdown")
	clock.advance_seconds(30.0)
	check(clock.get_phase() == "dawn" and
		is_equal_approx(clock.get_time_remaining_in_phase(), 30.0) and
		is_equal_approx(clock.get_phase_elapsed_seconds(), 30.0),
		"mid-dawn time remaining and elapsed are queryable")
	clock.advance_seconds(30.0)
	check(clock.get_phase() == "day" and
		is_equal_approx(clock.get_time_remaining_in_phase(), 360.0),
		"dawn exits precisely at 60 seconds and day begins")
	check(clock._clock_label.text.contains("DAY  ·  06:00 LEFT"),
		"day begins with six-minute visible countdown")
	clock.advance_seconds(359.0)
	check(clock.get_phase() == "day" and
		is_equal_approx(clock.get_phase_remaining_seconds(), 1.0),
		"day persists for 360 seconds")
	clock.advance_seconds(1.0)
	check(clock.get_phase() == "dusk" and
		is_equal_approx(clock.get_phase_remaining_seconds(), 120.0),
		"dusk starts exactly after 6-minute day")
	clock.advance_seconds(75.0)
	check(clock.get_phase() == "dusk" and
		is_equal_approx(clock.get_phase_remaining_seconds(), 45.0),
		"last-45-second dusk query point is available without plant logic")
	check(clock._clock_label.text.contains("DUSK  ·  00:45 LEFT"),
		"existing neutral last-45s dusk window is visible to QA")
	clock.advance_seconds(45.0)
	check(clock.get_phase() == "night" and
		is_equal_approx(clock.get_phase_remaining_seconds(), 180.0),
		"night follows the complete 2-minute dusk")
	clock.advance_seconds(180.0)
	check(clock.get_phase() == "dawn" and clock.get_day() == 2 and
		is_equal_approx(clock.get_phase_remaining_seconds(), 60.0),
		"full 720-second cycle reaches next day's dawn")
	check(clock._clock_label.text.contains("DAY 2  ·  05:00") and
		clock._clock_label.text.contains("DAWN  ·  01:00 LEFT"),
		"clock HUD correctly advances to the next calendar day")
	check(starts == ["day", "dusk", "night", "dawn"],
		"phase_started emits each phase exactly once, in order")
	check(ends == ["dawn", "day", "dusk", "night"],
		"phase_ended emits each prior phase exactly once, in order")
	check(dusks == [1], "dusk_started existing subscriber API still fires once")
	clock.advance_seconds(1440.0)
	check(clock.get_day() == 4 and dusks == [1, 2, 3],
		"time skips emit every crossed dusk and retain cycle numbering")
	clock.set_total_minutes(540.0)
	starts.clear()
	ends.clear()
	clock.advance_seconds(0.0)
	check(starts.is_empty() and ends.is_empty(), "zero delta creates no transitions")
	clock.cycle_seconds = 360.0
	clock.set_total_minutes(300.0)
	check(is_equal_approx(clock.phase_duration_seconds("dawn"), 30.0),
		"optional QA cycle override preserves proportional phase sizes")
	check(clock._clock_label.text.contains("DAWN  ·  00:30 LEFT"),
		"HUD respects optional QA cycle scaling, never hardcodes a timer")
	check(Clock.phase_countdown_label(1020.0, 9, 44.01).contains("DUSK  ·  00:45 LEFT"),
		"HUD counts partial seconds up so it never shows zero before transition")
	clock.queue_free()

	if failed == 0:
		print("[DAY NIGHT CLOCK] PASS %d checks" % checks)
	else:
		push_error("[DAY NIGHT CLOCK] FAIL %d/%d" % [failed, checks])
	quit(1 if failed > 0 else 0)

func _on_started(phase_name: String, _day: int) -> void:
	starts.append(phase_name)

func _on_ended(phase_name: String, _day: int) -> void:
	ends.append(phase_name)

func _on_dusk(day: int) -> void:
	dusks.append(day)

func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failed += 1
		push_error("[DAY NIGHT CLOCK] " + description)
