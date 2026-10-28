extends SceneTree
## Regression for broken bridge caps and input after title scene removal.
const Bridge := preload("res://scripts/prologue_bridge_world.gd")
const Title := preload("res://scripts/title_screen.gd")
var checks := 0
var failures := 0
var navigations := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func _run() -> void:
	for far in [true, false]:
		for broken in [false, true]:
			for p in [Vector2.ZERO, Vector2(-1196, -145), Vector2(1100, 308)]:
				var cap := Bridge.post_cap_polygon(p, broken, far)
				_check(cap.size() == 6, "six cap vertices retained")
				_check(Geometry2D.triangulate_polygon(cap).size() == 12,
					"all front/back intact/broken caps triangulate into four triangles")
				var intact := Bridge.post_cap_polygon(p, false, far)
				for i in cap.size():
					_check(cap[i].is_equal_approx(intact[i] + Vector2(0, 10 if broken else 0)),
						"damage lowers the whole cap without crossing its outline")
	# Exercise every placement from the authored bridge's deterministic seeds.
	var broken_count := 0
	for far in [true, false]:
		var rng := RandomNumberGenerator.new()
		rng.seed = 808 if far else 909
		var x := -1196.0
		while x < 1245.0:
			var spread := rng.randf_range(174.0, 266.0)
			var broken := rng.randf() < 0.38
			if broken: broken_count += 1
			_check(not Geometry2D.triangulate_polygon(Bridge.post_cap_polygon(Vector2(x, -145 if far else 308), broken, far)).is_empty(), "every seeded bridge cap triangulates")
			x += spread
	_check(broken_count == 11, "fixture covers all eleven originally rejected caps")
	for stone in Bridge.flagstones_for(Rect2(-1280, -360, 2560, 720)):
		_check(not Geometry2D.triangulate_polygon(stone["polygon"]).is_empty(), "fallback flagstones remain valid")

	var title = Title.new()
	root.add_child(title)
	title.scene_changer = func(path: String):
		navigations += 1
		_check(path == "res://scenes/room_p1.tscn", "New Game retains bridge destination")
		_check(root.is_input_handled(), "accept consumed BEFORE scene removal")
		root.remove_child(title)
	var event := InputEventAction.new()
	event.action = "ui_accept"
	event.pressed = true
	title._input(event)
	_check(navigations == 1 and not title.is_inside_tree(), "transition removes title exactly once")
	title.free()
	await process_frame
	print("[OPENING RENDER] %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
