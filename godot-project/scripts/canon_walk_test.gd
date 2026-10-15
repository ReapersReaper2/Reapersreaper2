extends SceneTree
## Four genuine PNG strips must load and render without old-outfit mixing.
const Sprites := preload("res://scripts/mollosar_sprites.gd")
const Loader := preload("res://scripts/critical_sprite_loader.gd")
var failed: int = 0
var checks: int = 0
func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failed += 1
		push_error("[CANON WALK] " + message)
func _initialize() -> void:
	call_deferred("_run")
func _run() -> void:
	var loaded: Dictionary = {}
	for d in ["down", "up", "left", "right"]:
		var path := "res://sprites/mollosar/canon_walk/form1_walk_%s_spec384.png" % d
		var tex: Texture2D = Loader.load_texture(path)
		_check(tex != null, d + " sprite strip is loadable")
		if tex == null:
			continue
		_check(tex.get_width() == 2304 and tex.get_height() == 384, d + " valid six-cell dimensions")
		var im: Image = tex.get_image()
		for n in range(6):
			var frame := im.get_region(Rect2i(n*384, 0, 384, 384))
			var used := frame.get_used_rect()
			_check(used.has_area() and used.position.x >= 8 and used.end.x <= 376, d + " frame is not clipped")
			_check(used.end.y == 361, d + " frame feet grounded at y 360")
		loaded[d] = tex
	var manager = Sprites.new()
	manager._sprite = Sprite2D.new()
	manager._load_form(1)
	_check(manager._canon_walk_active, "all four canon directions activated atomically")
	_check(manager._idle.is_empty(), "no old-outfit idle artwork is shown between steps")
	for d in ["down", "up", "left", "right"]:
		_check(manager._strips.get(d) == loaded.get(d), d + " uses the new canon sprite")
		_check(int(manager._frames.get(d, 0)) == 6, d + " loops six frames")
	manager.free()
	print("[CANON WALK] %s %d checks" % ["PASS" if failed == 0 else "FAIL",checks])
	quit(1 if failed > 0 else 0)
