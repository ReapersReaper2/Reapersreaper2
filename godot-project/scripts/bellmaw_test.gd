extends SceneTree
## The Bellmaw puzzle-boss — headless test.
##
## Covers: verbatim Mollosar lines (BOTH "…Okay." instances), the
## stimulus experiment beats (wrong -> fail line, bloom -> advance),
## the no-HP-bar contract, the Luna-absent lock (superseded lines are
## NOT wired — asserted), flag wiring, and player-death reset.

const BellmawBossScript := preload("res://scripts/bellmaw_boss.gd")
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


func _make_boss(gs: Node) -> Node:
	var boss = BellmawBossScript.new()
	boss.game_state = gs
	root.add_child(boss)
	return boss


func _init() -> void:
	print("[bellmaw_test] starting")
	_run.call_deferred()


func _run() -> void:
	_test_verbatim_lines()
	_test_luna_absent_lock()
	_test_experiment_beats()
	_test_resolution()
	_test_no_hp_bar()
	_test_player_death_reset()
	var total := _passes + _failures
	print("[TEST] bellmaw: %d passed, %d failed (of %d)" % [_passes, _failures, total])
	if _failures > 0:
		quit(1)
	else:
		quit(0)


# --- Verbatim lines (06b THE BELLMAW — do not paraphrase) ---------------------

func _test_verbatim_lines() -> void:
	_check("observe line 1 verbatim", BellmawBossScript.LINE_OBSERVE_1 == "...Okay.")
	_check("observe line 2 verbatim", BellmawBossScript.LINE_OBSERVE_2 == "Okay.")
	_check("BOTH Okay instances wired (distinct consts)",
		BellmawBossScript.LINE_OBSERVE_1 != BellmawBossScript.LINE_OBSERVE_2)
	_check("fail line verbatim", BellmawBossScript.LINE_FAIL == "No. Not that.")
	_check("reveal line verbatim", BellmawBossScript.LINE_REVEAL == "...You.")
	_check("resolve line verbatim",
		BellmawBossScript.LINE_RESOLVE == "...You'd have had something to say.")
	_check("all lines are Mollosar's", BellmawBossScript.SPEAKER == "MOLLOSAR")


# --- Luna-absent lock (06b continuity lock; superseded lines NOT wired) --------

func _const_map() -> Dictionary:
	return (BellmawBossScript as GDScript).get_script_constant_map()


func _test_luna_absent_lock() -> void:
	# No line constant may belong to Luna.
	for const_name in ["LINE_OBSERVE_1", "LINE_OBSERVE_2", "LINE_FAIL",
			"LINE_REVEAL", "LINE_RESOLVE"]:
		var line: String = _const_map()[const_name]
		_check("line %s is not Luna's" % const_name, not ("LUNA" in line.to_upper()))
	# The script must never emit dialogue as Luna: no dialogue entry with a
	# Luna character is constructed anywhere in the source.
	var src := FileAccess.get_file_as_string("res://scripts/bellmaw_boss.gd")
	_check("no Luna dialogue entries wired", not src.contains('"character": "LUNA"'))
	_check("no Luna speaker wired", not src.contains('"LUNA"'))
	_check("speaker const is Mollosar", src.contains('SPEAKER := "MOLLOSAR"'))


# --- Experiment beats --------------------------------------------------------

func _test_experiment_beats() -> void:
	var gs = _make_gs()
	var boss = _make_boss(gs)
	var advanced: Array = []
	var failed: Array = []
	boss.experiment_advanced.connect(func(s): advanced.append(s))
	boss.experiment_failed.connect(func(s): failed.append(s))
	boss._phase = 2  # EXPERIMENT (skip the async observe timers)
	_check("correct stimulus is the bloom",
		BellmawBossScript.CORRECT_STIMULUS == BellmawBossScript.STIMULUS_BLOOM)
	# Wrong stimuli: movement, sound, sight, stone — all "Nothing."
	for wrong in [BellmawBossScript.STIMULUS_MOVEMENT, BellmawBossScript.STIMULUS_SOUND,
			BellmawBossScript.STIMULUS_SIGHT, BellmawBossScript.STIMULUS_STONE]:
		boss.offer_stimulus(wrong)
	_check("four wrong stimuli recorded", boss.attempt_count() == 4)
	_check("wrong stimuli stay in EXPERIMENT", boss._phase == 2)
	_check("fail signal fired per wrong stimulus", failed.size() == 4)
	_check("no advance on wrong stimuli", advanced.is_empty())
	# The bloom: advance.
	boss.offer_stimulus(BellmawBossScript.STIMULUS_BLOOM)
	_check("bloom advances to REVEAL", boss._phase == 3)
	_check("advance signal fired for bloom", advanced == ["bloom"])
	# Stimuli after reveal: ignored.
	boss.offer_stimulus(BellmawBossScript.STIMULUS_STONE)
	_check("post-reveal stimulus ignored", boss.attempt_count() == 5)
	boss.queue_free()


# --- Resolution -----------------------------------------------------------------

func _test_resolution() -> void:
	var gs = _make_gs()
	var boss = _make_boss(gs)
	boss._phase = 3  # REVEAL
	boss._resolve()
	_check("resolve sets bellmaw_defeated", bool(gs.get_flag("bellmaw_defeated")))
	_check("phase RESOLVED", boss._phase == 4)
	_check("inactive after resolve", not boss.is_active())
	# Trigger a second time: already defeated -> no restart.
	var boss2 = _make_boss(gs)
	boss2._on_trigger_activated(null)
	_check("no restart once defeated", boss2._phase == 0)
	boss.queue_free()
	boss2.queue_free()


# --- No HP bar ---------------------------------------------------------------------

func _test_no_hp_bar() -> void:
	var gs = _make_gs()
	var boss = _make_boss(gs)
	_check("bellmaw has no vigor property", not ("vigor" in boss))
	_check("bellmaw has no take_hit method", not boss.has_method("take_hit"))
	_check("bellmaw has no max_vigor const",
		not ("MAX_VIGOR" in _const_map()))
	boss.queue_free()


# --- Player death: puzzle resets, no game-over --------------------------------------

func _test_player_death_reset() -> void:
	var gs = _make_gs()
	var boss = _make_boss(gs)
	boss._phase = 2
	boss.offer_stimulus(BellmawBossScript.STIMULUS_SOUND)
	_check("one attempt recorded", boss.attempt_count() == 1)
	boss._on_player_died()
	_check("death resets to IDLE", boss._phase == 0)
	_check("death clears attempts", boss.attempt_count() == 0)
	_check("defeat flag untouched by reset", not bool(gs.get_flag("bellmaw_defeated")))
	boss.queue_free()
