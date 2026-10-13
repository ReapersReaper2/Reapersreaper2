extends SceneTree
## Painted, collision-free Reserve archway / ruin regression for all garden rooms.
## godot --headless --path godot-project --script res://scripts/garden_painted_arches_test.gd

const GardenWorld := preload("res://scripts/garden_world.gd")
const Crumbled := preload("res://assets/environment/reserve_crumbling_arch_v1.png")
const Gateway := preload("res://assets/environment/reserve_stone_archway_v1.png")
const Gd1 := preload("res://scenes/room_gd1.tscn")
const Gd2 := preload("res://scenes/room_gd2.tscn")
const Gd3 := preload("res://scenes/room_gd3.tscn")

var _failures := 0
var _checks := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_check(Crumbled is Texture2D and Gateway is Texture2D,
		"approved environment assets import as textures")
	_check(Crumbled.get_size() == Vector2(512, 512) and
		Gateway.get_size() == Vector2(512, 512),
		"original Muse 512px masters remain intact")
	for source in [
			"res://assets/environment/reserve_crumbling_arch_v1.png",
			"res://assets/environment/reserve_stone_archway_v1.png"]:
		var bytes := FileAccess.get_file_as_bytes(source)
		_check(bytes.size() > 200000 and bytes[0] == 137 and
			bytes[1] == 80 and bytes[2] == 78 and bytes[3] == 71,
			"approved image is a real bundled PNG, not a Git LFS stub")
	var ruin_layout: Dictionary = GardenWorld._visible_placement(
		Crumbled, GardenWorld.LANDMARK_DISPLAY_HEIGHT)
	var gate_layout: Dictionary = GardenWorld._visible_placement(
		Gateway, GardenWorld.EXIT_GATE_DISPLAY_HEIGHT)
	_check(not ruin_layout.is_empty() and not gate_layout.is_empty(),
		"both painted sprites have nonempty silhouettes")
	_check(float(ruin_layout["factor"]) > 0.0 and
		float(gate_layout["factor"]) > 0.0,
		"painted arch sprites receive positive scale")

	var room := Node2D.new()
	room.name = "GardenPaintedArchTest"
	root.add_child(room)
	var garden = GardenWorld.new()
	garden.use_painted_ground = false
	garden.bounds = Rect2(-640, -360, 1280, 720)
	garden.density = 0.0
	garden.landmark = Vector2(100, 10)
	garden.shrine = Vector2(-350, 200)
	room.add_child(garden)
	_check(garden.has_painted_landmarks() and garden.get_painted_arch_count() == 3,
		"the central ruin and two exit gates are painted, not polygons")
	var points := {
		"PaintedGardenRuin": garden.landmark,
		"PaintedWestTrailArch": Vector2(-570, 100),
		"PaintedEastTrailArch": Vector2(570, 100)
	}
	for name in points.keys():
		var arch := garden.get_node_or_null(name) as Sprite2D
		_check(arch != null, "painted landmark node exists: " + name)
		if arch == null:
			continue
		_check(arch.position.is_equal_approx(points[name]),
			"approved art is at the authored narrative/exit point")
		_check(not arch.z_as_relative and arch.z_index >= -1900 and
			arch.z_index <= 1900, "painted stone is world-depth sorted")
		_check(arch.get_child_count() == 0,
			"painted arch adds no child collider or touch-intercepting UI")
		var used: Rect2i = arch.texture.get_image().get_used_rect()
		# Source-image bottom is alpha silhouette foot, not padded PNG edge.
		var foot_y := (float(used.end.y) - float(arch.texture.get_height()) * 0.5 +
			arch.offset.y) * arch.scale.y + arch.position.y
		_check(absf(foot_y - float(points[name].y)) < 0.1,
			"transparent artwork feet align to the existing exit/landmark position")
	_check((garden.get_node("PaintedEastTrailArch") as Sprite2D).flip_h,
		"eastern arch reverses its asymmetry for less repeated composition")
	_check(garden._walkway(Vector2(-570, 100)) and
		garden._walkway(Vector2(570, 100)) and
		garden._walkway(garden.landmark),
		"original paths remain traversable after artwork replacement")

	for item in [Gd1, Gd2, Gd3]:
		var authored: Node = item.instantiate()
		var authored_garden := authored.get_node_or_null("PlayableGarden")
		_check(authored_garden != null and bool(authored_garden.get("use_painted_landmarks")),
			"garden room defaults to approved painted stonework")
		_check(authored.get_node_or_null("Walls") != null and
			authored.get_node_or_null("Player") != null and
			authored.get_node_or_null("ExitEast") != null and
			authored.get_node_or_null("ExitWest") != null,
			"existing scene collision, spawn and transition triggers remain")
		authored.free()

	var fallback := GardenWorld.new()
	fallback.use_painted_landmarks = false
	fallback.use_painted_ground = false
	fallback.bounds = Rect2(-640, -360, 1280, 720)
	fallback.density = 0.0
	room.add_child(fallback)
	_check(not fallback.has_painted_landmarks() and
		fallback.get_painted_arch_count() == 0,
		"procedural ruin and gate fallback remains available")
	room.queue_free()

	if _failures == 0:
		print("[GARDEN PAINTED ARCHES] PASS %d checks" % _checks)
	else:
		push_error("[GARDEN PAINTED ARCHES] FAIL %d/%d" % [_failures, _checks])
	quit(1 if _failures > 0 else 0)

func _check(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("[GARDEN PAINTED ARCHES] " + description)
