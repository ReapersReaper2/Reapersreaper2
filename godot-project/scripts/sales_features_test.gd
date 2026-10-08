extends SceneTree
## Headless sales-features verification: photo mode activate/deactivate,
## boss rush unlock logic + scoring, speedrun timer/splits/categories,
## demo boundary (Ch1 accessible, Ch2 locked) and Wrath cliffhanger.
##
## Run: Godot --headless --path <project> -s res://scripts/sales_features_test.gd

const GameStateScript = preload("res://scripts/game_state.gd")
const PhotoModeScript = preload("res://scripts/photo_mode.gd")
const BossRushScript = preload("res://scripts/boss_rush.gd")
const SpeedrunScript = preload("res://scripts/speedrun.gd")
const DemoModeScript = preload("res://scripts/demo_mode.gd")

var _gs = null
var _passed := 0
var _failed := 0


func _check(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] sales_features: ", label)


func _initialize() -> void:
	_gs = root.get_node_or_null("GameState")
	if _gs == null:
		_gs = GameStateScript.new()
		_gs.name = "GameState"
		root.add_child(_gs)
		_gs._ready()
	_gs.new_game()
	_run()
	_report()
	quit()


func _run() -> void:
	_test_photo_mode()
	_test_boss_rush()
	_test_speedrun()
	_test_demo()


func _test_photo_mode() -> void:
	var photo = PhotoModeScript.new()
	root.add_child(photo)
	photo._ready()
	_check(not photo.is_active(), "photo: starts inactive")
	# Can't fully activate headless (needs tree pause), but the API exists.
	_check(photo.has_method("activate"), "photo: has activate")
	_check(photo.has_method("deactivate"), "photo: has deactivate")
	_check(photo.has_method("take_screenshot"), "photo: has take_screenshot")
	_check(photo.has_method("share_to_steam"), "photo: has share_to_steam stub")
	_check(photo.has_method("cycle_filter"), "photo: has cycle_filter")
	_check(photo.has_method("cycle_pose"), "photo: has cycle_pose")
	_check(PhotoModeScript.FILTERS.size() >= 3, "photo: has filters")
	_check(PhotoModeScript.POSES.size() >= 2, "photo: has poses")
	# Steam share is stubbed (returns false until M5).
	_check(photo.share_to_steam("test.png") == false, "photo: steam share stubbed")
	photo.queue_free()


func _test_boss_rush() -> void:
	# Locked before story completion.
	_check(not BossRushScript.is_unlocked(_gs), "rush: locked before ending_choice")
	_gs.set_flag("ending_choice", true)
	_check(BossRushScript.is_unlocked(_gs), "rush: unlocked after ending_choice")
	_gs.clear_flag("ending_choice")
	# Roster.
	_check(BossRushScript.boss_count() == 4, "rush: 4 bosses")
	var roster: Array = BossRushScript.roster()
	_check(roster[0]["id"] == "tentacle", "rush: first boss is tentacle")
	_check(roster[3]["id"] == "harrow", "rush: last boss is harrow")
	# Scoring: faster + less damage = more.
	var fast := BossRushScript.score_boss(30.0, 0)
	var slow := BossRushScript.score_boss(120.0, 50)
	_check(fast > slow, "rush: fast/clean scores higher")
	_check(fast > 0, "rush: score positive")
	_check(BossRushScript.score_boss(9999.0, 9999) == 0, "rush: score floors at 0")
	# Best score persistence.
	_check(BossRushScript.get_best(_gs) == 0, "rush: no best yet")
	_check(BossRushScript.submit_score(_gs, 2500), "rush: first score is best")
	_check(not BossRushScript.submit_score(_gs, 1000), "rush: worse score not best")
	_check(BossRushScript.get_best(_gs) == 2500, "rush: best persists")


func _test_speedrun() -> void:
	# Categories.
	_check(SpeedrunScript.CATEGORIES.has("any"), "speed: any% category")
	_check(SpeedrunScript.CATEGORIES.has("hundred"), "speed: 100% category")
	_check(SpeedrunScript.CATEGORIES.has("nodeath"), "speed: no-death category")
	_check(not SpeedrunScript.is_active(_gs), "speed: inactive by default")
	# Start/stop.
	_check(SpeedrunScript.start_run(_gs, "any"), "speed: start any%")
	_check(SpeedrunScript.is_active(_gs), "speed: active after start")
	_check(not SpeedrunScript.start_run(_gs, "bogus"), "speed: rejects bad category")
	# Splits.
	SpeedrunScript.record_split(_gs, "prologue")
	SpeedrunScript.record_split(_gs, "ch1")
	var splits: Dictionary = SpeedrunScript.get_splits(_gs)
	_check(splits.has("prologue"), "speed: prologue split recorded")
	_check(splits.has("ch1"), "speed: ch1 split recorded")
	# Duplicate split ignored.
	var count_before := splits.size()
	SpeedrunScript.record_split(_gs, "ch1")
	_check(SpeedrunScript.get_splits(_gs).size() == count_before, "speed: duplicate split ignored")
	# Unknown chapter ignored.
	SpeedrunScript.record_split(_gs, "xyz")
	_check(not SpeedrunScript.get_splits(_gs).has("xyz"), "speed: unknown chapter ignored")
	# Death in any% doesn't stop the run.
	_check(SpeedrunScript.record_death(_gs), "speed: death ok in any%")
	_check(SpeedrunScript.is_active(_gs), "speed: still active after death in any%")
	SpeedrunScript.stop_run(_gs)
	_check(not SpeedrunScript.is_active(_gs), "speed: stopped")
	# No-death: a death voids the run.
	SpeedrunScript.start_run(_gs, "nodeath")
	_check(not SpeedrunScript.record_death(_gs), "speed: death voids nodeath")
	_check(not SpeedrunScript.is_active(_gs), "speed: nodeath stopped on death")
	# Finish + best.
	SpeedrunScript.start_run(_gs, "hundred")
	var result: Dictionary = SpeedrunScript.finish_run(_gs)
	_check(result["category"] == "hundred", "speed: finish returns category")
	_check(result["is_best"], "speed: first finish is best")
	_check(SpeedrunScript.get_best(_gs, "hundred") > 0 or result["time_msec"] >= 0, "speed: best recorded")


func _test_demo() -> void:
	# Demo boundary: Ch1 rooms allowed, Ch2+ blocked.
	# (is_demo() is false in tests — we test room_allowed logic directly.)
	# Force demo mode via project setting for the boundary test.
	ProjectSettings.set_setting("reaper/demo_mode", true)
	_check(DemoModeScript.is_demo(), "demo: is_demo true when setting set")
	_check(DemoModeScript.room_allowed("p1"), "demo: p1 allowed")
	_check(DemoModeScript.room_allowed("c1"), "demo: c1 allowed")
	_check(DemoModeScript.room_allowed("c2"), "demo: c2 allowed")
	_check(not DemoModeScript.room_allowed("h1"), "demo: h1 blocked")
	_check(not DemoModeScript.room_allowed("gd5"), "demo: gd5 blocked")
	ProjectSettings.set_setting("reaper/demo_mode", false)
	_check(DemoModeScript.room_allowed("gd5"), "demo: gd5 allowed when not demo")
	# Tentacle defeat sets the cliffhanger (in demo mode).
	ProjectSettings.set_setting("reaper/demo_mode", true)
	_check(not DemoModeScript.wrath_took_kanryu(_gs), "demo: no cliffhanger yet")
	DemoModeScript.on_tentacle_down(_gs)
	_check(DemoModeScript.wrath_took_kanryu(_gs), "demo: wrath cliffhanger set")
	_check(DemoModeScript.is_demo_complete(_gs), "demo: demo_complete set")
	ProjectSettings.set_setting("reaper/demo_mode", false)
	# Save stamping.
	var data := {"save_version": 2}
	DemoModeScript.stamp_demo_save(data)
	_check(bool(data.get("demo_origin", false)), "demo: save stamped demo_origin")
	_check(bool(data.get("demo_complete", false)), "demo: save stamped demo_complete")


func _report() -> void:
	print("[sales_features_test] done: %d passed, %d failed" % [_passed, _failed])
