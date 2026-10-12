extends SceneTree
## Gameplay playtime should advance in world/battle scenes but not on
## the title screen or under pause; saves retain the accumulated seconds.
## godot --headless --path godot-project --script res://scripts/playtime_test.gd

const GameStateScript := preload("res://scripts/game_state.gd")

var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var gs := GameStateScript.new()
	root.add_child(gs)
	gs.new_game()
	_check(is_zero_approx(float(gs.state["playtime"])), "new game starts at zero seconds")
	_check(GameStateScript.is_gameplay_scene("res://scenes/room_p1.tscn"),
		"prologue counts as gameplay")
	_check(GameStateScript.is_gameplay_scene("res://scenes/room_gd1.tscn"),
		"Reserve overworld counts as gameplay")
	_check(GameStateScript.is_gameplay_scene("res://scenes/battle.tscn"),
		"combat counts as gameplay")
	_check(GameStateScript.is_gameplay_scene("res://scenes/garden_refuge.tscn"),
		"Garden Refuge interior counts as gameplay")
	_check(not GameStateScript.is_gameplay_scene("res://scenes/title_screen.tscn"),
		"title screen does not count as gameplay")
	_check(not GameStateScript.is_gameplay_scene("res://scenes/settings.tscn"),
		"settings do not count as gameplay")
	_check(not GameStateScript.is_gameplay_scene("res://scenes/test_room.tscn"),
		"test harness scene does not inflate player saves")
	gs._process(12.0)
	_check(is_zero_approx(float(gs.state["playtime"])),
		"no current scene means no phantom playtime")
	var title := _activate_scene("res://scenes/title_screen.tscn")
	gs._process(12.0)
	_check(is_zero_approx(float(gs.state["playtime"])),
		"title idle does not inflate timer")
	_close_scene(title)

	var room := _activate_scene("res://scenes/room_p1.tscn")
	gs._process(1.5)
	_check(is_equal_approx(float(gs.state["playtime"]), 1.5),
		"playtime advances during exploration")
	paused = true
	gs._process(10.0)
	_check(is_equal_approx(float(gs.state["playtime"]), 1.5),
		"pause menu stops game timer")
	paused = false
	gs._process(3.25)
	_check(is_equal_approx(float(gs.state["playtime"]), 4.75),
		"timer resumes without losing existing playtime")
	gs.add_playtime(-50.0)
	_check(is_equal_approx(float(gs.state["playtime"]), 4.75),
		"negative deltas cannot lower total time")
	_close_scene(room)

	var battle := _activate_scene("res://scenes/battle.tscn")
	gs._process(6.0)
	_check(is_equal_approx(float(gs.state["playtime"]), 10.75),
		"battle seconds accumulate with exploration")
	_close_scene(battle)

	var json := JSON.stringify(gs.state)
	var decoded = JSON.parse_string(json)
	_check(decoded is Dictionary and
		is_equal_approx(float((decoded as Dictionary).get("playtime", -1.0)), 10.75),
		"normal JSON save preserves recorded time")
	gs.new_game()
	_check(is_zero_approx(float(gs.state["playtime"])),
		"starting another game resets only that playthrough's clock")
	gs.queue_free()
	if failures == 0:
		print("[PLAYTIME] PASS %d checks" % checks)
	else:
		push_error("[PLAYTIME] FAIL %d/%d" % [failures, checks])
	quit(1 if failures > 0 else 0)

func _activate_scene(path: String) -> Node2D:
	var fake := Node2D.new()
	fake.scene_file_path = path
	root.add_child(fake)
	current_scene = fake
	return fake

func _close_scene(scene: Node2D) -> void:
	current_scene = null
	root.remove_child(scene)
	scene.free()

func _check(ok: bool, msg: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("[PLAYTIME] " + msg)
