extends SceneTree
## Ch13-14 depower mechanics — headless test.
##
## Covers: state transitions (none -> full -> partial -> none), scythe
## damage modifiers, form gating + GameState.set_form enforcement,
## walk-speed modifier, combat-assist/map-sense/plant-ability/flight
## queries, HUD state labels, and the depower indicator.

const Depower = preload("res://scripts/depower.gd")
const GameStateScript := preload("res://scripts/game_state.gd")
const IndicatorScript := preload("res://scripts/depower_indicator.gd")

var _failures := 0
var _passes := 0


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


func _init() -> void:
	print("[depower_test] starting")
	_run.call_deferred()


func _run() -> void:
	_test_state_transitions()
	_test_damage_mult()
	_test_walk_speed()
	_test_form_gating()
	_test_set_form_enforcement()
	_test_queries()
	_test_labels()
	_test_indicator()
	var total := _passes + _failures
	print("[TEST] depower: %d passed, %d failed (of %d)" % [_passes, _failures, total])
	if _failures > 0:
		quit(1)
	else:
		quit(0)


func _test_state_transitions() -> void:
	var gs = _make_gs()
	_check("fresh state is NONE", Depower.state(gs) == Depower.State.NONE)
	gs.set_flag("ch13_depowered")
	_check("depower flag -> FULL", Depower.state(gs) == Depower.State.FULL)
	_check("is_depowered true", Depower.is_depowered(gs))
	gs.set_flag("ch13_repowered_partial")
	_check("partial flag -> PARTIAL", Depower.state(gs) == Depower.State.PARTIAL)
	_check("is_partial true", Depower.is_partial(gs))
	_check("not is_depowered at partial", not Depower.is_depowered(gs))
	gs.set_flag("ch13_repowered")
	_check("repower flag -> NONE", Depower.state(gs) == Depower.State.NONE)
	# Flag combos that must NOT depower.
	var gs2 = _make_gs()
	gs2.set_flag("ch13_repowered_partial")
	_check("partial alone is NONE", Depower.state(gs2) == Depower.State.NONE)
	var gs3 = _make_gs()
	gs3.set_flag("ch13_repowered")
	_check("repower alone is NONE", Depower.state(gs3) == Depower.State.NONE)
	var gs4 = _make_gs()
	gs4.set_flag("ch13_depowered")
	gs4.set_flag("ch13_repowered")
	_check("repower overrides depower", Depower.state(gs4) == Depower.State.NONE)
	_check("null gs is NONE", Depower.state(null) == Depower.State.NONE)


func _test_damage_mult() -> void:
	var gs = _make_gs()
	_check("NONE damage 1.0", Depower.damage_mult(gs) == 1.0)
	gs.set_flag("ch13_depowered")
	_check("FULL damage 0.5", Depower.damage_mult(gs) == 0.5)
	gs.set_flag("ch13_repowered_partial")
	_check("PARTIAL damage 0.75", Depower.damage_mult(gs) == 0.75)


func _test_walk_speed() -> void:
	var gs = _make_gs()
	_check("NONE speed 1.0", Depower.walk_speed_mult(gs) == 1.0)
	gs.set_flag("ch13_depowered")
	_check("FULL speed 0.85", Depower.walk_speed_mult(gs) == 0.85)
	gs.set_flag("ch13_repowered_partial")
	_check("PARTIAL speed 1.0", Depower.walk_speed_mult(gs) == 1.0)


func _test_form_gating() -> void:
	var gs = _make_gs()
	gs.set_flag("ch13_depowered")
	_check("FULL allows form 1", Depower.can_use_form(gs, 1))
	_check("FULL allows form 2", Depower.can_use_form(gs, 2))
	_check("FULL allows form 3 (locked Ch13-14 canon)", Depower.can_use_form(gs, 3))
	_check("FULL refuses form 4 (armor)", not Depower.can_use_form(gs, 4))
	_check("FULL refuses form 9", not Depower.can_use_form(gs, 9))
	gs.set_flag("ch13_repowered_partial")
	_check("PARTIAL allows form 3 (weak plant)", Depower.can_use_form(gs, 3))
	_check("PARTIAL refuses form 4", not Depower.can_use_form(gs, 4))
	gs.set_flag("ch13_repowered")
	_check("NONE allows form 9", Depower.can_use_form(gs, 9))


func _test_set_form_enforcement() -> void:
	var gs = _make_gs()
	gs.set_flag("ch13_depowered")
	gs.set_form(5)
	_check("set_form(5) refused while FULL (stays 1)", gs.get_form() == 1)
	gs.set_form(2)
	_check("set_form(2) allowed while FULL", gs.get_form() == 2)
	gs.set_form(3)
	_check("set_form(3) allowed while FULL (story-bot correction)", gs.get_form() == 3)
	gs.set_form(4)
	_check("set_form(4) refused while FULL (stays 3)", gs.get_form() == 3)
	gs.set_flag("ch13_repowered_partial")
	gs.set_form(3)
	_check("set_form(3) allowed while PARTIAL", gs.get_form() == 3)
	gs.set_form(4)
	_check("set_form(4) refused while PARTIAL (stays 3)", gs.get_form() == 3)
	gs.set_flag("ch13_repowered")
	gs.set_form(9)
	_check("set_form(9) allowed when repowered", gs.get_form() == 9)


func _test_queries() -> void:
	var gs = _make_gs()
	_check("assist on when NONE", Depower.combat_assist_enabled(gs))
	_check("map sense on when NONE", Depower.map_sense_unlocked(gs))
	_check("plant abilities on when NONE", Depower.plant_abilities_available(gs))
	_check("flight off without form9 flag", not Depower.flight_available(gs))
	gs.set_flag("form9_unlocked")
	_check("flight on when NONE + form9 flag", Depower.flight_available(gs))
	gs.set_flag("ch13_depowered")
	_check("assist off when FULL", not Depower.combat_assist_enabled(gs))
	_check("map sense off when FULL", not Depower.map_sense_unlocked(gs))
	_check("plant abilities off when FULL", not Depower.plant_abilities_available(gs))
	_check("flight off when FULL even with form9", not Depower.flight_available(gs))
	gs.set_flag("ch13_repowered_partial")
	_check("assist on when PARTIAL", Depower.combat_assist_enabled(gs))
	_check("map sense on when PARTIAL", Depower.map_sense_unlocked(gs))
	_check("plant abilities on when PARTIAL", Depower.plant_abilities_available(gs))
	_check("flight off when PARTIAL (needs full repower)", not Depower.flight_available(gs))


func _test_labels() -> void:
	var gs = _make_gs()
	_check("NONE label empty", Depower.state_label(gs) == "")
	gs.set_flag("ch13_depowered")
	_check("FULL label DEPOWERED", Depower.state_label(gs) == "DEPOWERED")
	gs.set_flag("ch13_repowered_partial")
	_check("PARTIAL label WEAKENED", Depower.state_label(gs) == "WEAKENED")


func _test_indicator() -> void:
	var gs = _make_gs()
	# Inject the test GameState directly: /root/GameState is the real
	# autoload in -s runs, which the indicator would otherwise resolve.
	var ind = IndicatorScript.new()
	root.add_child(ind)
	ind._ready()  # cold tree: _ready may not have fired yet
	ind._game_state = gs
	_check("indicator has label", ind._label != null)
	ind._process(0.016)
	_check("indicator hidden when NONE", not ind._label.visible)
	gs.set_flag("ch13_depowered")
	ind._process(0.016)
	_check("indicator visible when FULL", ind._label.visible)
	_check("indicator text DEPOWERED when FULL", ind._label.text == "DEPOWERED")
	gs.set_flag("ch13_repowered_partial")
	ind._process(0.016)
	_check("indicator text WEAKENED when PARTIAL", ind._label.text == "WEAKENED")
	gs.set_flag("ch13_repowered")
	ind._process(0.016)
	_check("indicator hidden when repowered", not ind._label.visible)
	root.remove_child(ind)
	ind.queue_free()
	gs.queue_free()
