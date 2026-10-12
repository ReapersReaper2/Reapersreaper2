extends SceneTree
## Verify the assets that must appear on the opening bridge EVEN if the
## normal .png files are Git LFS pointer stubs.
## godot --headless --path godot-project --script res://scripts/prologue_visual_test.gd
const Loader := preload("res://scripts/critical_sprite_loader.gd")
const Mollosar := preload("res://scripts/mollosar_sprites.gd")
const NPC := preload("res://scripts/npc.gd")
var passed := 0
var failed := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	for facing in ["down", "up", "left", "right"]:
		var path := "res://sprites/mollosar/form1_walk_%s_spec384.png" % facing
		var texture := Loader.load_texture(path)
		_check(texture != null, "Mollosar %s sprite loads" % facing)
		if texture != null:
			_check(texture.get_width() == 1536, "Mollosar %s four frames" % facing)
			_check(texture.get_height() == 384, "Mollosar %s frame height" % facing)
		_check(Mollosar._load_tex(path) != null, "sprite manager reads %s art" % facing)
	for name in ["mira", "wounded_soldier"]:
		var path := "res://assets/npc/%s.png" % name
		var texture := NPC._load_tex(path)
		_check(texture != null, "%s artwork loads" % name)
		if texture != null:
			_check(texture.get_width() == 1024 and texture.get_height() == 1536,
				"%s portrait has proper master dimensions" % name)
	var idle := Loader.load_texture("res://sprites/mollosar/form1_idle_down_spec384.png")
	_check(idle != null and idle.get_width() == 768 and idle.get_height() == 384,
		"Form 1 idle animation loads two actual frames")
	var bridge := Loader.load_texture("res://assets/backgrounds/p1_bellhollow_bridge_1280x720.png")
	_check(bridge != null and bridge.get_width() == 1280 and bridge.get_height() == 720,
		"Opening skyline loads without LFS")
	_check(FileAccess.file_exists("res://assets/critical_sprites/form1_walk_down_spec384.b64"),
		"critical art bundled in project")
	print("[PROLOGUE ART TEST] %d passed / %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)

func _check(ok: bool, label: String) -> void:
	if ok:
		passed += 1
	else:
		failed += 1
		push_error("[PROLOGUE ART TEST] FAIL: " + label)
