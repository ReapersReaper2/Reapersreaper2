extends SceneTree
## User's Android recording showed Bellhollow scenery gray and Mollosar as
## a greybox. These exact existing approved masters must load at runtime.
## No new art is created or approved by this test.
const Loader := preload("res://scripts/critical_sprite_loader.gd")
var failed: int = 0
var checked: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var originals := [
		"res://sprites/mollosar/form1_walk_down_spec384.png",
		"res://sprites/mollosar/form1_walk_up_spec384.png",
		"res://sprites/mollosar/form1_walk_left_spec384.png",
		"res://sprites/mollosar/form1_walk_right_spec384.png",
		"res://sprites/mollosar/form1_idle_down_spec384.png",
		"res://assets/backgrounds/p1_bellhollow_bridge_1280x720.png",
		"res://assets/npc/mira.png",
		"res://assets/npc/wounded_soldier.png",
	]
	for path in originals:
		var tex: Texture2D = Loader.load_texture(path)
		check(tex != null and tex.get_width() >= 384 and tex.get_height() >= 170,
			"runtime load approved source image: " + path)
	for facing in ["down", "up", "left", "right"]:
		var path := "res://sprites/mollosar/form1_walk_" + facing + "_spec384.png"
		check(Loader.has_source(path),
			"mortal sprite source discoverable before greybox fallback: " + facing)
	if failed == 0:
		print("[ESSENTIAL MOBILE ART] PASS %d checks" % checked)
	else:
		push_error("[ESSENTIAL MOBILE ART] FAIL %d/%d" % [failed, checked])
	quit(1 if failed > 0 else 0)

func check(ok: bool, label: String) -> void:
	checked += 1
	if not ok:
		failed += 1
		push_error("[ESSENTIAL MOBILE ART] " + label)
