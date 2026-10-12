extends SceneTree
## Deterministic synthetic-art regression: per-cell feet, cached offsets,
## and reap-swing grounding. No LFS checkout required.
## godot --headless --path godot-project --script res://scripts/sprite_grounding_test.gd

const Mgr := preload("res://scripts/mollosar_sprites.gd")
var _checks := 0
var _failed := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var sheet := Image.create(Mgr.CELL * 2, Mgr.CELL, false, Image.FORMAT_RGBA8)
	sheet.fill(Color.TRANSPARENT)
	sheet.fill_rect(Rect2i(20, 200, 30, 100), Color.WHITE) # foot y = 300
	sheet.fill_rect(Rect2i(Mgr.CELL + 20, 200, 30, 140), Color.WHITE) # y = 340
	var first: float = Mgr.grounding_offset_for_frame(sheet, 0)
	var second: float = Mgr.grounding_offset_for_frame(sheet, 1)
	_check(is_equal_approx(first, 20.8), "frame 0 measures its own alpha bounds")
	_check(is_equal_approx(second, 4.8), "frame 1 measures its own alpha bounds")
	_check(first - second > 10.0, "neighbor frame cannot change foot anchor")
	_check(is_equal_approx(Mgr.grounding_offset_for_frame(sheet, 2), Mgr.SPRITE_Y_OFFSET),
		"out-of-range frame uses safe default")
	var empty := Image.create(Mgr.CELL, Mgr.CELL, false, Image.FORMAT_RGBA8)
	empty.fill(Color.TRANSPARENT)
	_check(is_equal_approx(Mgr.grounding_offset_for_frame(empty, 0), Mgr.SPRITE_Y_OFFSET),
		"transparent cell uses safe default")

	var mgr = Mgr.new()
	var display := Sprite2D.new()
	mgr._sprite = display
	var texture := ImageTexture.create_from_image(sheet)
	mgr._apply_grounding(texture, 0)
	_check(is_equal_approx(display.position.y, first), "cached walk frame 0 grounding")
	mgr._apply_grounding(texture, 1)
	_check(is_equal_approx(display.position.y, second), "cached walk frame 1 grounding")
	_check(mgr._ground_offsets.size() == 2, "cache keys distinguish texture frames")
	mgr._apply_grounding(texture, 0)
	_check(is_equal_approx(display.position.y, first), "cache returns first frame anchor")
	mgr._swing_tex = texture
	mgr._swing_frames = 2
	mgr._swinging = true
	mgr._frame = 1
	mgr._draw_frame()
	_check(display.region_rect.position.x == float(Mgr.CELL), "swing selects second cell")
	_check(is_equal_approx(display.position.y, second), "swing uses frame-local grounding")
	display.free()
	mgr.free()
	if _failed == 0:
		print("[SPRITE GROUNDING TEST] PASS %d checks" % _checks)
	else:
		push_error("[SPRITE GROUNDING TEST] FAIL %d/%d" % [_failed, _checks])
	quit(1 if _failed > 0 else 0)

func _check(ok: bool, description: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
		push_error("[SPRITE GROUNDING TEST] " + description)
