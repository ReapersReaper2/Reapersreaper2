extends SceneTree
## Production regression: native Muse terrain textures, softened trail mask,
## and unchanged gameplay route/tree collision under the new painted ground.
## godot --headless --path godot-project --script res://scripts/garden_painted_ground_test.gd

const GardenWorld := preload("res://scripts/garden_world.gd")
const PaintedShader := preload("res://scripts/garden_ground_paint.gdshader")
const Grass := preload("res://assets/environment/garden_grass_a_v2.png")
const Path := preload("res://assets/environment/garden_dirtpath_v2.png")
const GD1 := preload("res://scenes/room_gd1.tscn")
const GD2 := preload("res://scenes/room_gd2.tscn")
const GD3 := preload("res://scenes/room_gd3.tscn")

var _checks := 0
var _failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_check(Grass != null and Grass.get_size() == Vector2(512, 512),
		"Muse grass-a-v2 is a native 512px terrain texture")
	_check(Path != null and Path.get_size() == Vector2(512, 512),
		"Muse dirtpath-v2 is a native 512px terrain texture")
	_check(FileAccess.get_file_as_bytes(
		"res://assets/environment/garden_grass_a_v2.png").size() == 520961,
		"native painted grass matches original source bytes; no LFS stub")
	_check(FileAccess.get_file_as_bytes(
		"res://assets/environment/garden_dirtpath_v2.png").size() == 517198,
		"native dirt path matches original source bytes; no LFS stub")
	_check(PaintedShader != null and PaintedShader is Shader,
		"native Godot shader can be imported alongside art files")

	var scenes: Array[PackedScene] = [GD1, GD2, GD3]
	for i in range(scenes.size()):
		var room := scenes[i].instantiate()
		# A free-standing fixture avoids triggering the scene's other
		# encounters and saves; the route parameters are copied exactly.
		var authored = room.get_node_or_null("PlayableGarden")
		_check(authored != null, "garden scene %d retains the authored world" % i)
		if authored == null:
			room.free()
			continue
		var world = GardenWorld.new()
		world.name = "PaintedGardenFixture"
		world.bounds = authored.bounds
		world.seed_value = authored.seed_value
		world.density = 0.0 # Test paint without spawning hundreds of trees.
		world.landmark = authored.landmark
		world.shrine = authored.shrine
		world.feature_points = authored.feature_points
		root.add_child(world)
		_check(world.has_painted_ground(), "room %d creates painted ground by default" % i)
		var overlay := world.get_node_or_null("PaintedGardenGround") as ColorRect
		_check(overlay != null and overlay.mouse_filter == Control.MOUSE_FILTER_IGNORE,
			"painted floor in room %d never steals touch inputs" % i)
		if overlay != null:
			_check(overlay.show_behind_parent and overlay.position == world.bounds.position,
				"room %d floor is behind rocks, trees and world decorations" % i)
			_check(overlay.size.is_equal_approx(world.bounds.size),
				"room %d painted area covers full walkable region" % i)
			var mat := overlay.material as ShaderMaterial
			_check(mat != null and mat.shader == PaintedShader,
				"room %d uses texture-blend rather than 64px color rectangles" % i)
			if mat != null:
				_check(mat.get_shader_parameter("grass_texture") == Grass and
					mat.get_shader_parameter("path_texture") == Path,
					"room %d uses actual connected Muse PNGs" % i)
				_check((mat.get_shader_parameter("world_tiling") as Vector2).is_equal_approx(
					world.bounds.size / 512.0),
					"all rooms keep the same 512 world px texture scale")
		var mask: Image = world.get_painted_mask()
		_check(mask != null and mask.get_width() > 80 and mask.get_height() > 60,
			"room %d uses sufficiently smooth sampled trail mask" % i)
		if mask != null:
			var route_center := Vector2(world.bounds.get_center().x,
				world._route_y(world.bounds.get_center().x))
			var on_trail: float = _mask_at(world, mask, route_center)
			_check(on_trail > 0.90,
				"room %d's exit-to-exit walkable trail is actually painted" % i)
			_check(world._walkway(route_center),
				"room %d still routes collision-free along the painted trail" % i)
			_check(_mask_at(world, mask, world.landmark) > 0.91 and
				_mask_at(world, mask, world.shrine) > 0.91,
				"room %d preserves both story landmark and shrine clearings" % i)
			var y_edge := world._route_y(route_center.x) + 110.0
			var transition := _mask_at(world, mask, Vector2(route_center.x, y_edge))
			_check(transition > 0.15 and transition < 0.85,
				"room %d has soft blended grass/path edges instead of square tiles" % i)
		world.queue_free()
		room.free()

	# The previously supported colored floor is still a rollback switch.
	var legacy = GardenWorld.new()
	legacy.use_painted_ground = false
	legacy.density = 0.0
	root.add_child(legacy)
	_check(not legacy.has_painted_ground() and legacy.get_painted_mask() == null,
		"explicit rollback mode keeps old procedural terrain without textures")
	_check(legacy._walkway(Vector2(0.0, legacy._route_y(0.0))),
		"rollback and painted modes share the same gameplay path rules")
	legacy.queue_free()

	if _failures == 0:
		print("[GARDEN PAINTED GROUND] PASS %d checks" % _checks)
	else:
		push_error("[GARDEN PAINTED GROUND] FAIL %d/%d" % [_failures, _checks])
	quit(1 if _failures > 0 else 0)

func _mask_at(world: Node2D, mask: Image, point: Vector2) -> float:
	var rect: Rect2 = world.get("bounds")
	var local: Vector2 = (point - rect.position) / rect.size
	var xi := clampi(int(floor(local.x * float(mask.get_width()))), 0, mask.get_width() - 1)
	var yi := clampi(int(floor(local.y * float(mask.get_height()))), 0, mask.get_height() - 1)
	return mask.get_pixel(xi, yi).r

func _check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		push_error("[GARDEN PAINTED GROUND] " + message)
