extends SceneTree
## Android regression: Black Sand Shore must render something darker than
## the engine clear color even when the only PNG is a Git LFS pointer.
const ShoreRoom := preload("res://scripts/room_p3.gd")
const ShoreFallback := preload("res://scripts/prologue_black_sand_fallback.gd")
const CriticalSpriteLoader := preload("res://scripts/critical_sprite_loader.gd")
const P3_PATH := "res://assets/backgrounds/p3_black_sand_shore_1280x720.png"

var checks: int = 0
var failed: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failed += 1
		push_error("[P3 BACKDROP] " + label)

func _run() -> void:
	var room := ShoreRoom.new()
	var bg := Sprite2D.new()
	bg.name = "Background"
	room.add_child(bg)
	
	# We intentionally avoid the full room's _ready by calling on a small
	# handmade Node2D fixture? The room _ready() may still run here, but
	# this fixture does not need a Player and the fallback is idempotent.
	room._ensure_shore_art()
	var texture := CriticalSpriteLoader.load_texture(P3_PATH)
	var valid_art := texture != null and texture.get_width() >= 640 and texture.get_height() >= 360
	if valid_art:
		_check(bg.texture != null, "valid imported art must take priority")
		_check(room.get_node_or_null("ShoreFallback") == null, "never overlay valid art")
	else:
		var fallback = room.get_node_or_null("ShoreFallback")
		_check(fallback != null, "missing shore art must render a fallback")
		_check(fallback is ShoreFallback, "fallback must use deterministic dark-shore renderer")
		_check(fallback.z_index < bg.z_index, "fallback belongs behind actors and HUD")
		_check(bg.texture == null, "broken LFS stub must not remain visible")
	room._ensure_shore_art()
	_check(room.get_children().filter(func(child: Node) -> bool: return child.name == "ShoreFallback").size() == (0 if valid_art else 1), "shore art installation must be idempotent")
	room.queue_free()
	print("[P3 BACKDROP] %s %d checks" % ["PASS" if failed == 0 else "FAIL", checks])
	quit(1 if failed > 0 else 0)
