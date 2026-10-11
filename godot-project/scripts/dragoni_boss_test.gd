extends SceneTree
## Mount Dragoni boss fight — headless test.
##
## Covers: verbatim wave barks (Dragoni constraint), wave sequencing,
## pressed-hard armor-fracture beat (fires once), scripted-loss terminal
## state (victory is never a win state), player-death falling through to
## the loss beat, flag wiring, and SummitBoss scene attach point.

const DragoniBossScript := preload("res://scripts/dragoni_boss.gd")
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


func _const_map() -> Dictionary:
	return (DragoniBossScript as GDScript).get_script_constant_map()


func _make_boss(gs: Node) -> Node:
	var boss = DragoniBossScript.new()
	boss.game_state = gs
	root.add_child(boss)
	return boss


func _init() -> void:
	print("[dragoni_boss_test] starting")
	_run.call_deferred()


func _run() -> void:
	_test_verbatim_barks()
	_test_wave_sequencing()
	_test_pressed_hard()
	_test_scripted_loss()
	_test_player_death_falls_through()
	_test_scene_wiring()
	var total := _passes + _failures
	print("[TEST] dragoni_boss: %d passed, %d failed (of %d)" % [_passes, _failures, total])
	if _failures > 0:
		quit(1)
	else:
		quit(0)


# --- Verbatim barks (act2-boss-text.md §1 — Dragoni constraint) -----------

func _test_verbatim_barks() -> void:
	_check("wave 1 bark verbatim",
		DragoniBossScript.BARK_WAVE_1 == "Oni. Broken tusks, no clan marks. Nobody owns these.")
	_check("wave 2 bark verbatim",
		DragoniBossScript.BARK_WAVE_2 == "Reapers — they're cutting at the vines. Someone taught them.")
	_check("wave 3 bark verbatim",
		DragoniBossScript.BARK_WAVE_3 == "Hold the pattern. He tires. Everything tires.")
	_check("pressed-hard bark verbatim",
		DragoniBossScript.BARK_PRESSED_HARD == "Your chest — the armor's cracking —")
	_check("wave 1 speaker is LUNA", DragoniBossScript.BARK_SPEAKER_WAVE_1 == "LUNA")
	_check("wave 2 speaker is LUNA", DragoniBossScript.BARK_SPEAKER_WAVE_2 == "LUNA")
	_check("wave 3 speaker is ALDER", DragoniBossScript.BARK_SPEAKER_WAVE_3 == "ALDER")
	_check("pressed-hard speaker is LUNA", DragoniBossScript.BARK_SPEAKER_PRESSED_HARD == "LUNA")
	# Blast trigger: no new line — 06b governs verbatim. There must be no
	# blast bark constant to drift from the story text.
	_check("no blast bark constant (06b governs)",
		not ("BARK_BLAST" in _const_map()))
	_check("bark cap is 2s", DragoniBossScript.BARK_MAX_SECONDS == 2.0)


# --- Wave sequencing ------------------------------------------------------

func _test_wave_sequencing() -> void:
	var gs = _make_gs()
	var boss = _make_boss(gs)
	_check("3 waves defined", DragoniBossScript.WAVES.size() == 3)
	_check("wave 1 is oni", DragoniBossScript.WAVES[0]["name"] == "oni")
	_check("wave 2 is dark_reapers", DragoniBossScript.WAVES[1]["name"] == "dark_reapers")
	_check("wave 3 is shika", DragoniBossScript.WAVES[2]["name"] == "shika")
	var started: Array = []
	boss.wave_started.connect(func(idx): started.append(idx))
	boss._begin_wave(0)
	_check("wave 0 begins", boss.current_wave() == 0)
	_check("wave_started fired for 0", started == [0])
	_check("fighting during waves", boss.is_fighting())
	boss._on_wave_cleared()
	_check("wave 1 follows wave 0", boss.current_wave() == 1)
	_check("wave_started fired for 1", started == [0, 1])
	boss._on_wave_cleared()
	_check("wave 2 follows wave 1", boss.current_wave() == 2)
	_check("wave_started fired for 2", started == [0, 1, 2])
	boss.queue_free()


# --- Pressed-hard beat -----------------------------------------------------

func _test_pressed_hard() -> void:
	var gs = _make_gs()
	var boss = _make_boss(gs)
	boss._begin_wave(2)
	_check("pressed-hard unfired at wave start", not boss._pressed_hard_fired)
	boss._on_pressed_hard()
	_check("pressed-hard fires once", boss._pressed_hard_fired)
	boss._on_pressed_hard()
	_check("pressed-hard does not refire", boss._pressed_hard_fired)
	# Outside fighting: no fire.
	var boss2 = _make_boss(gs)
	boss2._on_pressed_hard()
	_check("pressed-hard silent outside fight", not boss2._pressed_hard_fired)
	boss.queue_free()
	boss2.queue_free()


# --- Scripted loss: the terminal state --------------------------------------

func _test_scripted_loss() -> void:
	var gs = _make_gs()
	var boss = _make_boss(gs)
	var loss_fired := [false]
	boss.scripted_loss.connect(func(): loss_fired[0] = true)
	boss._begin_wave(2)
	boss._on_wave_cleared()  # final wave cleared -> scripted loss, never a win
	_check("scripted loss is terminal", boss.in_scripted_loss())
	_check("scripted_loss signal fired", loss_fired[0])
	_check("ch12_complete flag set", bool(gs.get_flag("ch12_complete")))
	_check("blast_supermove flag set", bool(gs.get_flag("blast_supermove")))
	_check("no longer fighting after loss", not boss.is_fighting())
	boss.queue_free()


# --- Player death: falls through to the loss beat, never game-over ----------

func _test_player_death_falls_through() -> void:
	var gs = _make_gs()
	var boss = _make_boss(gs)
	boss._begin_wave(1)
	boss._on_player_died()
	_check("player death -> scripted loss", boss.in_scripted_loss())
	_check("ch12_complete set on death path", bool(gs.get_flag("ch12_complete")))
	boss.queue_free()
	# Idle: death does nothing.
	var boss2 = _make_boss(gs)
	gs.set_flag("ch12_complete", false)
	boss2._on_player_died()
	_check("player death idle: no loss", not boss2.in_scripted_loss())
	boss2.queue_free()


# --- Scene wiring ------------------------------------------------------------

func _test_scene_wiring() -> void:
	var d2t := FileAccess.get_file_as_string("res://scenes/room_d2.tscn")
	_check("d2: SummitBoss trigger node present", d2t.contains("SummitBoss"))
	_check("d2: trigger name matches controller", d2t.contains('name="SummitBoss"'))
	_check("d2: DragoniBossFight controller node present", d2t.contains("DragoniBossFight"))
	_check("d2: dragoni_boss.gd wired", d2t.contains("scripts/dragoni_boss.gd"))
	_check("d2: WaveSpawner node present (P1 pattern)", d2t.contains('name="WaveSpawner"'))
	_check("d2: wave_spawner.gd wired", d2t.contains("scripts/wave_spawner.gd"))
	_check("d2: invader_spawn markers present", d2t.contains('"invader_spawn"'))
