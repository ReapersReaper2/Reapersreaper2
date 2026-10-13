extends SceneTree
## Approved art integration: 4 solid garden-tree variants + live refuge art.
## godot --headless --path godot-project --script res://scripts/garden_painted_landmarks_test.gd
const GardenTree := preload("res://scripts/garden_tree.gd")
const GardenWorld := preload("res://scripts/garden_world.gd")
const Cottage := preload("res://scripts/garden_cottage.gd")
const GardenRoom := preload("res://scenes/room_gd1.tscn")

const ART := [
	"res://assets/environment/garden_tree_twisted_oak_v2.png",
	"res://assets/environment/garden_tree_willow_v2.png",
	"res://assets/environment/garden_tree_dead_v2.png",
	"res://assets/environment/garden_tree_bonewhite_v1.png",
	"res://assets/environment/garden_refuge_cottage_v2.png",
]
const EXPECTED_HEIGHTS := [512, 512, 512, 512, 341]
const EXPECTED_BYTES := [347410, 398019, 237892, 103469, 240108]

var _checks := 0
var _failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	for i in range(ART.size()):
		var source := ART[i]
		_check(FileAccess.file_exists(source), "approved artwork is in repository: " + source)
		_check(FileAccess.get_file_as_bytes(source).size() == EXPECTED_BYTES[i],
			"approved image bytes are intact and not a Git LFS pointer: " + source)
		var tex := load(source) as Texture2D
		_check(tex != null and tex.get_width() == 512 and
			tex.get_height() == EXPECTED_HEIGHTS[i],
			"native transparent master dimensions are correct")
		if tex != null:
			var img := tex.get_image()
			_check(img != null and not img.is_empty() and img.get_pixel(0, 0).a <= 0.05,
				"painted foliage/building corners are alpha-transparent")

	var variants: Dictionary = {}
	for x in range(-10, 11):
		for y in range(-5, 6):
			var point := Vector2(float(x * 64 + 32), float(y * 64 + 32))
			var v: int = GardenTree.variant_for_position(point, 117)
			_check(v >= 0 and v <= 3 and
				v == GardenTree.variant_for_position(point, 117),
				"tree species is stable and does not use random global state")
			variants[v] = true
	_check(variants.size() == 4, "all four approved tree variants occur in the garden")

	for i in range(4):
		var tree = GardenTree.new()
		tree.name = "SolidTree"
		tree.position = Vector2(250 + float(i) * 110.0, 100)
		tree.tree_variant = i
		root.add_child(tree)
		var art := tree.get_node_or_null("PaintedTreeArt") as Sprite2D
		var collision := tree.get_node_or_null("TrunkCollision") as CollisionShape2D
		_check(tree.has_painted_tree() and art != null,
			"tree %d uses a live Sprite2D with approved cutout art" % i)
		_check(collision != null and collision.shape is CircleShape2D and
			is_equal_approx((collision.shape as CircleShape2D).radius, 24.0),
			"painted tree %d retains its original solid trunk collider" % i)
		_check(collision != null and collision.position == Vector2(0, 18) and
			absf(tree.get_visual_foot_y() - 18.0) <= 0.05,
			"tree %d roots align with the existing physical trunk baseline" % i)
		_check(tree.z_as_relative == false and tree.z_index == 118,
			"tree %d keeps world-depth sorting against Mollosar" % i)
		tree.free()

	var fallback = GardenTree.new()
	fallback.use_painted_tree = false
	root.add_child(fallback)
	_check(not fallback.has_painted_tree() and
		fallback.get_node_or_null("TrunkCollision") != null,
		"procedural tree fallback remains solid and usable")
	fallback.free()

	var garden = GardenWorld.new()
	garden.bounds = Rect2(-256, -192, 512, 384)
	garden.seed_value = 117
	garden.density = 0.63
	garden.use_painted_ground = false
	root.add_child(garden)
	var trees := 0
	for child in garden.get_children():
		if child.name == "SolidTree":
			trees += 1
			_check(child.tree_variant == GardenTree.variant_for_position(child.position, 117),
				"GardenWorld chooses art variant deterministically without moving tree")
	_check(trees > 0, "generator instantiates real painted tree residents")
	garden.free()

	var cottage = Cottage.new()
	root.add_child(cottage)
	var facade := cottage.get_node_or_null("PaintedCottageFacade") as Sprite2D
	_check(cottage.has_painted_facade() and facade != null,
		"garden cottage uses hand-painted approved building asset")
	_check(facade != null and absf(cottage.get_doorstep_y() - 64.0) < 6.0,
		"painted cottage doorway sits at the authored entry trigger")
	if facade != null:
		_check(facade.texture.get_width() == 512 and facade.texture.get_height() == 341,
			"refuge facade remains a transparent 512x341 Muse composition")
	cottage.free()
	var fallback_cottage = Cottage.new()
	fallback_cottage.use_painted_facade = false
	root.add_child(fallback_cottage)
	_check(not fallback_cottage.has_painted_facade(),
		"original procedural refuge art remains opt-in fallback")
	fallback_cottage.free()

	# Scene-level invariant: artwork changes are visual, not routes or doors.
	var room = GardenRoom.instantiate()
	_check(room.get_node_or_null("GardenRefugeCottage") != null and
		room.get_node_or_null("CottageWalls") != null and
		room.get_node_or_null("EnterGardenRefuge") != null,
		"painted cottage retains separately-authored door and solid walls")
	_check(room.get_node("EnterGardenRefuge").position == Vector2(-500, 118),
		"existing refugee entrance is not displaced")
	_check(room.get_node_or_null("Player") != null and
		room.get_node_or_null("ShrineGd1") != null and
		room.get_node_or_null("Creatures") != null,
		"garden story nodes, five species and starting player remain")
	room.free()

	if _failures == 0:
		print("[GARDEN PAINTED LANDMARKS] PASS %d checks" % _checks)
	else:
		push_error("[GARDEN PAINTED LANDMARKS] FAIL %d/%d" % [_failures, _checks])
	quit(1 if _failures > 0 else 0)

func _check(ok: bool, description: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		push_error("[GARDEN PAINTED LANDMARKS] " + description)
