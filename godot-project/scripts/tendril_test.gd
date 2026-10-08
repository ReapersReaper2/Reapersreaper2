extends SceneTree
## Tendril traversal — headless test.
##
## Covers: script loads, depower gating (FULL blocks / PARTIAL+N ONE allow),
## grab/ride/release cycle, waypoint movement, destination reached,
## player locks set + restored, ride signals, repeat rides, mid-ride
## invulnerability (tendril_riding), and no-ride on bad input.

const TendrilScript := preload("res://scripts/tendril.gd")
const GameStateScript := preload("res://scripts/game_state.gd")
const PlayerScript := preload("res://scripts/player.gd")

var _failures := 0
var _passes := 0


class MockRider extends Node2D:
	var move_locked := false
	var input_locked := false
	var tendril_riding := false


func _check(name: String, cond: bool) -> void:
	if cond:
		_passes += 1
	else:
		_failures += 1
		print("  FAILED: ", name)


func _make_gs() -> Node:
	var gs = GameStateScript.new()
	gs.save_system = null
	gs.new_game()
	return gs


func _make_tendril() -> Area2D:
	var t = TendrilScript.new()
	t.waypoints = PackedVector2Array([Vector2(0, -450), Vector2(-200, -200), Vector2(-400, 100)])
	t.ride_speed = 10000.0  # fast: tests finish in a few ticks
	t.flag = "test_tendril_ridden"
	return t


func _init() -> void:
	print("[tendril_test] starting")
	_run.call_deferred()


func _run() -> void:
	_test_loads()
	_test_depower_gating()
	_test_ride_cycle()
	_test_bad_input()
	_test_invulnerability()
	var total := _passes + _failures
	print("[TEST] tendril: %d passed, %d failed (of %d)" % [_passes, _failures, total])
	if _failures > 0:
		quit(1)
	else:
		quit(0)


func _test_loads() -> void:
	var t = TendrilScript.new()
	_check("tendril script instantiates", t != null)
	_check("default prompt text", t.prompt_text == "[E] grab tendril")
	_check("not riding by default", not t.is_riding())
	_check("default ride speed sane", t.ride_speed > 0.0)
	t.free()


func _test_depower_gating() -> void:
	var gs = _make_gs()
	var t = _make_tendril()
	_check("can_grab with NONE depower", t.can_grab(gs))
	_check("can_grab with null gs", t.can_grab(null))
	gs.set_flag("ch13_depowered")
	_check("can_grab blocked with FULL depower", not t.can_grab(gs))
	gs.set_flag("ch13_repowered_partial")
	_check("can_grab allowed with PARTIAL depower", t.can_grab(gs))
	gs.set_flag("ch13_repowered")
	_check("can_grab allowed when repowered", t.can_grab(gs))
	# start_ride respects the gate too.
	var gs2 = _make_gs()
	gs2.set_flag("ch13_depowered")
	var t2 = _make_tendril()
	var rider = MockRider.new()
	_check("start_ride blocked with FULL depower", not t2.start_ride(rider, gs2))
	_check("not riding after blocked start", not t2.is_riding())
	_check("rider locks untouched after blocked start", not rider.tendril_riding)
	t.free()
	t2.free()
	rider.free()


func _test_ride_cycle() -> void:
	var gs = _make_gs()
	var t = _make_tendril()
	var rider = MockRider.new()
	var started := [false]
	var finished := [false]
	t.ride_started.connect(func(_x): started[0] = true)
	t.ride_finished.connect(func(_x): finished[0] = true)

	_check("start_ride succeeds", t.start_ride(rider, gs))
	_check("is_riding after start", t.is_riding())
	_check("ride_started emitted", started[0])
	_check("move_locked set", rider.move_locked)
	_check("input_locked set", rider.input_locked)
	_check("tendril_riding set", rider.tendril_riding)
	_check("rider snapped to path start", rider.global_position == Vector2(0, -450))
	_check("second start_ride while riding fails", not t.start_ride(rider, gs))

	# Tick until the ride completes.
	var ticks := 0
	while t.is_riding() and ticks < 100:
		var done: bool = t.tick_ride(0.016)
		if done:
			# _physics_process would call _finish_ride; emulate it.
			t._finish_ride()
		ticks += 1
	_check("ride completes", not t.is_riding())
	_check("ride_finished emitted", finished[0])
	_check("rider reached destination", rider.global_position == Vector2(-400, 100))
	_check("move_locked restored", not rider.move_locked)
	_check("input_locked restored", not rider.input_locked)
	_check("tendril_riding cleared", not rider.tendril_riding)
	# Repeat rides work (tendrils are reusable).
	_check("second ride allowed", t.start_ride(rider, gs))
	_check("riding again", t.is_riding())
	t.free()
	rider.free()


func _test_bad_input() -> void:
	var gs = _make_gs()
	var t = TendrilScript.new()  # no waypoints
	var rider = MockRider.new()
	_check("start_ride fails with no waypoints", not t.start_ride(rider, gs))
	_check("not riding after bad start", not t.is_riding())
	t.waypoints = PackedVector2Array([Vector2(0, 0)])  # only one point
	_check("start_ride fails with one waypoint", not t.start_ride(rider, gs))
	_check("start_ride fails with null rider", not t.start_ride(null, gs))
	t.free()
	rider.free()


func _test_invulnerability() -> void:
	# The real player ignores damage while tendril_riding is set.
	var p = PlayerScript.new()
	_check("tendril_riding defaults false", p.tendril_riding == false)
	p.vigor = 3
	p.tendril_riding = true
	p.take_damage(2)
	_check("no damage while tendril_riding", p.vigor == 3)
	p.tendril_riding = false
	p.take_damage(1)
	_check("damage applies when not riding", p.vigor == 2)
	p.free()
