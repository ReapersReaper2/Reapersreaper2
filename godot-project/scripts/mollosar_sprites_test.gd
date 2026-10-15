extends SceneTree
## Headless Mollosar sprite-manager test: Form 1 sheets load, the sprite
## shows and the greybox hides, direction maps movement->strip, the
## Form 1 idle sheet animates while standing still, and LFS-pointer
## stubs are detected loudly instead of failing silently.
## Run: ./godot43 --headless --path <project> -s res://scripts/mollosar_sprites_test.gd
##
## Texture-dependent checks need the real PNGs (git LFS). When the
## sheets are LFS-pointer stubs the art checks SKIP with a clear
## message; only the static logic checks run.

const Mgr := preload("res://scripts/mollosar_sprites.gd")

var _failures: Array[String] = []
var _skips: Array[String] = []
var _ran := false


func _check(name: String, cond: bool) -> void:
	if cond:
		print("  PASS: ", name)
	else:
		_failures.append(name)
		print("  FAIL: ", name)


func _skip(name: String) -> void:
	_skips.append(name)
	print("  SKIP: ", name)


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_run()
	if _failures.is_empty():
		print("mollosar_sprites_test: ALL PASS (%d skipped)" % _skips.size())
	else:
		printerr("mollosar_sprites_test: %d FAILURES" % _failures.size())
	quit(1 if not _failures.is_empty() else 0)
	return false


func _make_player_mock() -> Node2D:
	# Mirrors scenes/player.tscn's Visuals subtree: greybox placeholders
	# the manager must hide once real sprites are showing.
	var visuals := Node2D.new()
	visuals.name = "Visuals"
	var cloak := Polygon2D.new()
	cloak.name = "Cloak"
	var hood := Polygon2D.new()
	hood.name = "Hood"
	var eyel := ColorRect.new()
	eyel.name = "EyeL"
	var scythe := Line2D.new()
	scythe.name = "Scythe"
	for c in [cloak, hood, eyel, scythe]:
		visuals.add_child(c)
	return visuals


func _run() -> void:
	print("== mollosar_sprites_test ==")

	# 1. Static logic: 8-direction -> 4-strip mapping.
	_check("strip_for right", Mgr.strip_for(Vector2(1, 0)) == "right")
	_check("strip_for left", Mgr.strip_for(Vector2(-1, 0.2)) == "left")
	_check("strip_for up", Mgr.strip_for(Vector2(0.3, -1)) == "up")
	_check("strip_for down", Mgr.strip_for(Vector2(-0.3, 1)) == "down")
	_check("strip_for down-left -> down", Mgr.strip_for(Vector2(-1, 1)) == "down")
	_check("strip_for up-right -> up", Mgr.strip_for(Vector2(1, -1)) == "up")

	# Canon weapon rig must sample the NEW charcoal/ivory character, not
	# the retired green-outfit texture geometry that produced detached blades.
	for d in ["down", "up", "left", "right"]:
		var geo: Dictionary = Mgr.mortal_blade_geometry(d)
		_check("canon sword geometry " + d, not geo.is_empty() and geo.has("guard") and geo.has("tip"))
		var source: Texture2D = Mgr._load_tex("res://sprites/mollosar/canon_walk/form1_walk_%s_spec384.png" % d)
		if source != null:
			var pixels: Image = source.get_image()
			var grip: Vector2i = Vector2i(geo["guard"])
			var point: Vector2i = Vector2i(geo["tip"])
			_check("canon sword guard painted " + d,
				grip.x >= 0 and grip.x < 384 and grip.y >= 0 and grip.y < 384 and pixels.get_pixelv(grip).a > 0.1)
			# Sword tips are narrow; allow a 6px search neighborhood for the
			# antialiased metal, but never accept coordinates on a distant limb.
			var tip_found := false
			for yy in range(maxi(0, point.y - 6), mini(384, point.y + 7)):
				for xx in range(maxi(0, point.x - 6), mini(384, point.x + 7)):
					if pixels.get_pixel(xx, yy).a > 0.1:
						tip_found = true
			_check("canon sword tip painted " + d, tip_found)

	# 2. LFS-pointer detection on a temp stub file.
	var stub := "user://_lfs_stub_test.png"
	var f := FileAccess.open(stub, FileAccess.WRITE)
	f.store_line("version https://git-lfs.github.com/spec/v1")
	f.store_line("oid sha256:deadbeef")
	f.close()
	_check("lfs pointer detected", Mgr._is_lfs_pointer(stub))
	DirAccess.remove_absolute(stub)
	_check("real png is not a pointer", not Mgr._is_lfs_pointer("res://icon.svg") if FileAccess.file_exists("res://icon.svg") else true)

	# 3. Texture-dependent checks need the real Form 1 sheets.
	if Mgr._load_tex("res://sprites/mollosar/form1_walk_down_spec384.png") == null:
		_check("bundled Form 1 art loads even when LFS fails", false)
		return

	var visuals := _make_player_mock()
	var root_kids_before := root.get_child_count()
	root.add_child(visuals)
	var mgr = Mgr.new()
	visuals.add_child(mgr)  # _ready fires on add (in-tree)
	_check("form defaults to 1", mgr.current_form() == 1)
	_check("has sprites", mgr.has_sprites())
	_check("walk strips loaded x4", mgr._strips.size() == 4)
	_check("idle matches active outfit", mgr._idle.is_empty() if mgr._canon_walk_active else mgr._idle.has("down"))
	_check("walk frame count", int(mgr._frames.get("down", 0)) == (6 if mgr._canon_walk_active else 4))
	_check("idle frame count matches outfit", int(mgr._idle_frames.get("down", 0)) == (0 if mgr._canon_walk_active else 2))
	_check("sprite visible", mgr._sprite.visible)
	for c in visuals.get_children():
		if c != mgr:
			_check("greybox hidden: " + c.name, not (c as CanvasItem).visible)
	_check("sprite grounded on capsule", mgr._sprite.position.y >= -28.0 and mgr._sprite.position.y <= 22.0)
	_check("walk FPS keeps legacy and canon rates", Mgr.WALK_FPS == 6.0 and Mgr.CANON_WALK_FPS == 10.0)
	_check("idle uses 1-1.5 fps", Mgr.IDLE_FPS >= 1.0 and Mgr.IDLE_FPS <= 1.5)

	# 4. Direction hook: facing selects the matching strip.
	mgr.tick(0.5, Vector2.LEFT, true)
	_check("left strip selected", mgr._strip_dir == "left")
	_check("left strip texture matches active walk", (mgr._sprite.texture as Texture2D).get_width() == (2304 if mgr._canon_walk_active else 1536))
	mgr.tick(0.5, Vector2.UP, true)
	_check("up strip selected", mgr._strip_dir == "up")
	mgr.tick(0.5, Vector2.RIGHT, true)
	_check("right strip selected", mgr._strip_dir == "right")
	# A diagonal joystick wobble must NOT keep restarting frame zero.
	mgr.tick(0.17, Vector2.LEFT, true)
	var phase_before := mgr._frame % int(mgr._frames["left"])
	_check("walking phase progressed before turn", phase_before > 0)
	mgr.tick(0.0, Vector2.UP, true)
	_check("direction change keeps stepping phase", mgr._frame % int(mgr._frames["up"]) == phase_before)
	mgr.tick(0.0, Vector2.LEFT, true)
	_check("return turn keeps stepping phase", mgr._frame % int(mgr._frames["left"]) == phase_before)
	# Walk animation advances frames across the 4-frame strip.
	mgr.tick(0.0, Vector2.DOWN, true)
	var x0: float = mgr._sprite.region_rect.position.x
	mgr.tick(0.2, Vector2.DOWN, true)
	_check("walk frame advances", mgr._sprite.region_rect.position.x != x0)

	# 5. Idle: standing still with an idle sheet animates it.
	mgr.tick(0.0, Vector2.DOWN, false)
	_check("idle respects the active outfit", (not mgr._idle_on) if mgr._canon_walk_active else mgr._idle_on)
	_check("idle texture retains same outfit", (mgr._sprite.texture as Texture2D).get_width() == (2304 if mgr._canon_walk_active else 768))
	var ix0: float = mgr._sprite.region_rect.position.x
	mgr.tick(0.85, Vector2.DOWN, false)
	_check("idle frame behavior", (mgr._sprite.region_rect.position.x == ix0) if mgr._canon_walk_active else (mgr._sprite.region_rect.position.x != ix0))
	# No idle sheet for left: falls back to walk frame 0, idle off.
	mgr.tick(0.0, Vector2.LEFT, false)
	_check("idle off without idle sheet", not mgr._idle_on)
	_check("walk strip frame 0 when idle-less", (mgr._sprite.texture as Texture2D).get_width() == (2304 if mgr._canon_walk_active else 1536) and mgr._sprite.region_rect.position.x == 0.0)
	# Moving again leaves idle mode.
	mgr.tick(0.0, Vector2.DOWN, true)
	_check("walk resumes from idle", not mgr._idle_on and (mgr._sprite.texture as Texture2D).get_width() == (2304 if mgr._canon_walk_active else 1536))

	# 6. Scythe-rig nodes are untouched: the manager only parents under
	# Visuals and never touches siblings outside it (verified by mock:
	# root's child count is unchanged apart from our own mock).
	_check("no side-effect children on root", root.get_child_count() == root_kids_before + 1)

	root.remove_child(visuals)
	visuals.queue_free()
