extends SceneTree
## Gravemaw witness — headless test.
##
## Covers: the witness contract (no attacks, no HP bar — he does not
## fight), the P1 invader-wave loop reuse, encounter end via the scene
## flag (never a defeat), and player-death loop reset.

const GravemawScript := preload("res://scripts/gravemaw_witness.gd")
const WaveSpawnerScript := preload("res://scripts/wave_spawner.gd")
const GameStateScript := preload("res://scripts/game_state.gd")

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


func _make_gravemaw(gs: Node) -> Node:
	var g = GravemawScript.new()
	g.game_state = gs
	root.add_child(g)
	return g


func _init() -> void:
	print("[gravemaw_test] starting")
	_run.call_deferred()


func _run() -> void:
	_test_witness_contract()
	_test_wave_loop_reuse()
	_test_encounter_end_via_flag()
	_test_player_death_resets_loop()
	var total := _passes + _failures
	print("[TEST] gravemaw: %d passed, %d failed (of %d)" % [_passes, _failures, total])
	if _failures > 0:
		quit(1)
	else:
		quit(0)


# --- Witness contract: he does not fight -----------------------------------------

func _test_witness_contract() -> void:
	var gs = _make_gs()
	var g = _make_gravemaw(gs)
	_check("gravemaw has no vigor property", not ("vigor" in g))
	_check("gravemaw has no take_hit method", not g.has_method("take_hit"))
	_check("gravemaw has no attack method", not g.has_method("attack"))
	_check("gravemaw emits no fight_won", not g.has_signal("fight_won"))
	_check("gravemaw signals encounter_ended", g.has_signal("encounter_ended"))
	g.queue_free()


# --- P1 invader-wave loop reuse ------------------------------------------------------

func _test_wave_loop_reuse() -> void:
	var gs = _make_gs()
	var g = _make_gravemaw(gs)
	_check("spawner attached", g._spawner != null)
	_check("spawner is the wave_spawner", g._spawner.get_script() == WaveSpawnerScript)
	_check("3 waves configured", GravemawScript.WAVES.size() == 3)
	_check("wave dicts carry counts", GravemawScript.WAVES[0].has("count"))
	var started := [false]
	g.encounter_started.connect(func(): started[0] = true)
	g.debug_start()
	_check("encounter starts witnessing", g.is_witnessing())
	_check("encounter_started fired", started[0])
	_check("spawner loop running", g._spawner._phase != 0)  # not IDLE
	g.queue_free()


# --- Encounter ends via the scene flag — never a defeat ----------------------------------

func _test_encounter_end_via_flag() -> void:
	var gs = _make_gs()
	var g = _make_gravemaw(gs)
	var ended := [false]
	g.encounter_ended.connect(func(): ended[0] = true)
	g.debug_start()
	_check("witness flag starts false", not bool(gs.get_flag("sq1_gravemaw_witnessed")))
	g._on_all_waves_cleared()
	_check("encounter done after waves", g.is_done())
	_check("witness flag set on end", bool(gs.get_flag("sq1_gravemaw_witnessed")))
	_check("encounter_ended fired", ended[0])
	_check("no longer witnessing", not g.is_witnessing())
	g.queue_free()
	# Once witnessed: no restart.
	var g2 = _make_gravemaw(gs)
	g2.debug_start()
	_check("no restart once witnessed", not g2.is_witnessing())
	g2.queue_free()


# --- Player death: the wave loop resets; the witness remains ----------------------------------

func _test_player_death_resets_loop() -> void:
	var gs = _make_gs()
	var g = _make_gravemaw(gs)
	g.debug_start()
	_check("witnessing before death", g.is_witnessing())
	var old_spawner = g._spawner
	g._on_player_died()
	_check("death returns to IDLE", not g.is_witnessing())
	_check("spawner rebuilt on death", g._spawner != old_spawner)
	_check("witness flag untouched by death", not bool(gs.get_flag("sq1_gravemaw_witnessed")))
	g.queue_free()
