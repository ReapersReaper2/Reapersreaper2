extends SceneTree
## Headless Mollosar sprite integration test.
## Run: ./Godot_v4.3-stable_linux.x86_64 --headless --path <project> -s res://scripts/sprite_test.gd
##
## Checks: all 10 forms x 4 directions load (form7 right falls back to
## mirrored left), frame counts (3 vs 4), 8-vector -> 4-strip mapping,
## form switching swaps the set, swing strip wiring, greybox fallback.

var _failures: Array[String] = []


func _check(name: String, cond: bool) -> void:
	if cond:
		print("  PASS: ", name)
	else:
		_failures.append(name)
		print("  FAIL: ", name)


func _make_mgr():
	var mgr = (load("res://scripts/mollosar_sprites.gd") as GDScript).new()
	# Parent it under a dummy Visuals node so greybox collection works.
	var visuals := Node2D.new()
	visuals.name = "Visuals"
	var grey := Polygon2D.new()
	grey.name = "Cloak"
	visuals.add_child(grey)
	root.add_child(visuals)
	visuals.add_child(mgr)
	# Explicit _ready(): under -s the tree is cold during _initialize,
	# so _ready doesn't fire on add_child (established test pattern).
	mgr._ready()
	return [mgr, grey]


func _initialize() -> void:
	print("sprite_test: starting")

	# --- 1. strip_for: 8 vectors -> 4 strips (dominant axis) ---
	var cases := [
		[Vector2(0, 1), "down"], [Vector2(0, -1), "up"],
		[Vector2(1, 0), "right"], [Vector2(-1, 0), "left"],
		[Vector2(0.7, 0.7), "down"], [Vector2(-0.7, 0.7), "down"],
		[Vector2(0.7, -0.7), "up"], [Vector2(-0.7, -0.7), "up"],
		[Vector2(1, 0.2), "right"], [Vector2(-1, -0.2), "left"],
	]
	var all_map := true
	for c in cases:
		var got: String = (load("res://scripts/mollosar_sprites.gd") as GDScript).strip_for(c[0])
		if got != c[1]:
			all_map = false
			print("  map mismatch: ", c[0], " -> ", got, " expected ", c[1])
	_check("8-vector -> 4-strip mapping correct", all_map)

	# --- 2. All 10 forms x 4 directions load ---
	var forms_ok := true
	var frame_info := {}
	for form in range(1, 11):
		var parts = _make_mgr()
		var mgr = parts[0]
		mgr._load_form(form)
		for d in ["down", "up", "left", "right"]:
			var tex: Texture2D = mgr._strips.get(d, null)
			if tex == null:
				forms_ok = false
				print("  MISSING strip: form", form, d)
			else:
				var n: int = int(mgr._frames.get(d, 0))
				frame_info["f%d_%s" % [form, d]] = n
				if tex.get_width() % 384 != 0:
					forms_ok = false
					print("  bad width: form", form, d, tex.get_width())
		mgr.get_parent().queue_free()
	_check("all 10 forms x 4 directions load (form7 right mirrored)", forms_ok)

	# --- 3. Frame counts: 3-frame strips where expected ---
	_check("form7 up is 3-frame", int(frame_info.get("f7_up", 0)) == 3)
	_check("form7 left is 3-frame", int(frame_info.get("f7_left", 0)) == 3)
	_check("form7 down is 4-frame", int(frame_info.get("f7_down", 0)) == 4)
	_check("form1 down is 4-frame", int(frame_info.get("f1_down", 0)) == 4)
	_check("form8 up is 4-frame", int(frame_info.get("f8_up", 0)) == 4)
	_check("form10 right is 4-frame", int(frame_info.get("f10_right", 0)) == 4)

	# --- 4. form7 right = true strip (retry-3 landed 2026-10-04) ---
	var parts7 = _make_mgr()
	var mgr7 = parts7[0]
	mgr7._load_form(7)
	_check("form7 right uses true strip, not mirror",
		mgr7._strips.has("right") and not bool(mgr7._strips.get("right_mirrored", false)))
	mgr7._set_strip("right")
	_check("form7 right does not flip_h", not mgr7._mirrored)
	mgr7._set_strip("down")
	_check("form7 down not mirrored", not mgr7._mirrored)
	parts7[0].get_parent().queue_free()

	# --- 5. Form switching swaps the sprite set ---
	var parts = _make_mgr()
	var mgr = parts[0]
	var grey = parts[1]
	mgr._load_form(1)
	var tex1: Texture2D = mgr._strips["down"]
	mgr._load_form(3)
	var tex3: Texture2D = mgr._strips["down"]
	_check("form switch 1->3 swaps texture", tex1 != tex3 and mgr.current_form() == 3)
	_check("greybox hidden when sprites present", not grey.visible)
	_check("sprite node visible when sprites present", mgr._sprite.visible)

	# --- 6. Swing strip (Form 3) ---
	_check("form3 has reap-swing strip", mgr._swing_tex != null and mgr._swing_frames == 4)
	mgr.play_swing()
	_check("play_swing enters swing mode", mgr._swinging)
	mgr.stop_swing()
	_check("stop_swing exits swing mode", not mgr._swinging)
	mgr._load_form(4)
	_check("form4 has no swing strip", mgr._swing_tex == null)
	mgr.play_swing()
	_check("play_swing no-op without strip", not mgr._swinging)

	# --- 7. Walk/idle frame advance ---
	mgr._load_form(1)
	mgr._set_strip("down")
	mgr.tick(0.0, Vector2.DOWN, false)
	_check("idle shows frame 0", mgr._frame == 0)
	mgr.tick(0.13, Vector2.DOWN, true)  # > 1/8s -> frame 1
	_check("walking advances frames", mgr._frame == 1)
	var r: Rect2 = mgr._sprite.region_rect
	_check("region rect tracks frame", r.position.x == 384.0 and r.size.x == 384.0)
	mgr.tick(0.0, Vector2.UP, true)
	_check("direction change swaps strip", mgr._strip_dir == "up")

	# --- 8. Greybox fallback when nothing loads ---
	var parts0 = _make_mgr()
	var mgr0 = parts0[0]
	var grey0 = parts0[1]
	mgr0._load_form(99)  # no such form
	_check("missing form -> no sprites", not mgr0.has_sprites())
	_check("missing form -> greybox stays visible", grey0.visible)
	parts0[0].get_parent().queue_free()
	parts[0].get_parent().queue_free()

	if _failures.is_empty():
		print("sprite_test: ALL TESTS PASSED")
	else:
		print("sprite_test: ", _failures.size(), " FAILURES")
	quit(0 if _failures.is_empty() else 1)
