extends SceneTree
## Offline-safe smoke test for the real opening assets, designed to fail
## loudly on broken LFS fallbacks rather than silently render polygons.
## godot --headless --path godot-project --script res://scripts/prologue_visual_smoke_test.gd

const Loader := preload("res://scripts/critical_sprite_loader.gd")
const Mgr := preload("res://scripts/mollosar_sprites.gd")

const REQUIRED := [
	["res://sprites/mollosar/form1_walk_down_spec384.png", 1536, 384],
	["res://sprites/mollosar/form1_walk_left_spec384.png", 1536, 384],
	["res://sprites/mollosar/form1_walk_right_spec384.png", 1536, 384],
	["res://sprites/mollosar/form1_walk_up_spec384.png", 1536, 384],
	["res://sprites/mollosar/form1_idle_down_spec384.png", 768, 384],
	["res://assets/npc/mira.png", 1024, 1536],
	["res://assets/npc/wounded_soldier.png", 1024, 1536],
]
var failed: int = 0
var checks: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	for item in REQUIRED:
		var path: String = item[0]
		var texture := Loader.load_texture(path)
		_check(texture != null, path + " must resolve actual PNG or bundled fallback")
		if texture != null:
			_check(texture.get_width() == int(item[1]), path + " expected width")
			_check(texture.get_height() == int(item[2]), path + " expected height")
	var main_scene: String = str(ProjectSettings.get_setting("application/run/main_scene", ""))
	_check(main_scene == "res://scenes/title_screen.tscn",
		"title screen should be the configured game entry")
	_check(Mgr.WALK_FPS == 6.0, "Mollosar walk should be 6fps")
	_check(Mgr.IDLE_FPS >= 1.0 and Mgr.IDLE_FPS <= 1.5,
		"Mollosar idle should be 1-1.5fps")
	if failed > 0:
		push_error("[PROLOGUE SMOKE] %d/%d FAILED" % [failed, checks])
	else:
		print("[PROLOGUE SMOKE] ALL %d CHECKS PASS" % checks)
	quit(1 if failed > 0 else 0)

func _check(result: bool, info: String) -> void:
	checks += 1
	if not result:
		failed += 1
		push_error("[PROLOGUE SMOKE] " + info)
