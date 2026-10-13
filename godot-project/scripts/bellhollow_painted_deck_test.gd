extends SceneTree
## Approved Muse art integration regression for Bellhollow Bridge.
## The painterly stone path must be a REAL binary PNG, not an LFS pointer
## nor a flat procedural rectangle; fallback and gameplay remain intact.
## godot --headless --path godot-project --script res://scripts/bellhollow_painted_deck_test.gd

const Bridge := preload("res://scripts/prologue_bridge_world.gd")
const Scene := preload("res://scenes/room_p1.tscn")
const Approved := preload("res://assets/environment/bellhollow_stonepath_source.png")
const SOURCE_PATH := "res://assets/environment/bellhollow_stonepath_source.png"

var _checks := 0
var _failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_check(Approved != null and Approved is Texture2D,
		"approved stonepath PNG imported as native Godot texture")
	_check(Approved.get_width() == 512 and Approved.get_height() == 512,
		"approved painted tile retains Muse's original 512px composition")
	_check(FileAccess.file_exists(SOURCE_PATH) and
		FileAccess.get_file_as_bytes(SOURCE_PATH).size() > 500000,
		"art is bundled as an actual binary image, never a Git LFS pointer")

	var source: Image = Approved.get_image()
	_check(source != null and not source.is_empty() and not source.is_compressed(),
		"approved source image can be color-graded without file modifications")

	var bridge = Bridge.new()
	bridge.bounds = Rect2(-1280, -360, 2560, 720)
	root.add_child(bridge)
	_check(bridge.has_painted_stone(),
		"new bridge uses the approved painted surface by default")
	_check(bridge.texture_repeat == CanvasItem.TEXTURE_REPEAT_ENABLED,
		"stonepath texture is enabled for repeated long-bridge drawing")
	if bridge.has_painted_stone():
		var toned: Image = bridge.get("_painted_stone").get_image()
		_check(toned.get_size() == source.get_size(),
			"runtime grading preserves source dimensions")
		var source_saturation := 0.0
		var result_saturation := 0.0
		var source_luminance := 0.0
		var result_luminance := 0.0
		for p in [Vector2i(36, 47), Vector2i(96, 124), Vector2i(161, 74),
				Vector2i(234, 195), Vector2i(305, 319), Vector2i(472, 408)]:
			var a: Color = source.get_pixelv(p)
			var b: Color = toned.get_pixelv(p)
			source_saturation += a.s
			result_saturation += b.s
			source_luminance += (a.r + a.g + a.b) / 3.0
			result_luminance += (b.r + b.g + b.b) / 3.0
		print("[BELLHOLLOW PALETTE] source saturation %.3f / toned %.3f; source lum %.3f / toned %.3f" %
			[source_saturation, result_saturation, source_luminance, result_luminance])
		_check(result_saturation < source_saturation,
			"Bellhollow palette reduces the Reserve tile's blue-green saturation")
		_check(result_luminance < source_luminance,
			"ash/soot pass darkens the source for the burning dusk panorama")
	bridge.queue_free()

	var fallback = Bridge.new()
	fallback.use_painted_stone = false
	# No need to draw obsolete polygons in the headless renderer.
	fallback.visible = false
	root.add_child(fallback)
	_check(not fallback.has_painted_stone(),
		"procedural stones stay available if painted surface is toggled off")
	_check(Bridge.flagstones_for(Rect2(-1280, -360, 2560, 720)).size() > 55,
		"existing fallback geometry still spans the playable bridge")
	fallback.queue_free()

	var p1 = Scene.instantiate()
	var authored = p1.get_node("WalkableBridge")
	_check(authored != null and authored.get_script() == Bridge,
		"prologue room keeps the existing bridge renderer and painted default")
	_check(p1.get_node_or_null("BattlefieldAtmosphere") != null,
		"smoke/embers/footstep ash are not removed by the texture upgrade")
	_check(p1.get_node_or_null("BridgeRails") != null and
		p1.get_node_or_null("TutorialTrigger") != null and
		p1.get_node_or_null("WaveSpawner") != null,
		"original bridge collision, tutorial and invader waves remain intact")
	_check(p1.get_node_or_null("Mira") != null and
		p1.get_node_or_null("Player") != null and
		p1.get_node_or_null("Luna") == null,
		"mortal Mollosar and Mira keep their original prologue scene")
	p1.free()

	if _failures == 0:
		print("[BEL L HOLLOW PAINTED DECK] PASS %d checks" % _checks)
	else:
		push_error("[BELLHOLLOW PAINTED DECK] FAIL %d/%d" % [_failures, _checks])
	quit(1 if _failures > 0 else 0)

func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		push_error("[BELLHOLLOW PAINTED DECK] " + label)
