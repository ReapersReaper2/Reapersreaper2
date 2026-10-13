extends SceneTree
## Muse-painted tree art integration. Explicit collision/layout and alpha
## checks guard against turning a 512px cutout into a black rectangle.
## godot --headless --path godot-project --script res://scripts/garden_painted_trees_test.gd

const PaintedGardenTree := preload("res://scripts/garden_tree.gd")
const Garden := preload("res://scripts/garden_world.gd")
const Oak := preload("res://assets/environment/garden_tree_oak_v2.png")
const Willow := preload("res://assets/environment/garden_tree_willow_v2.png")
const Dead := preload("res://assets/environment/garden_tree_dead_v2.png")

const PATHS := [
	"res://assets/environment/garden_tree_oak_v2.png",
	"res://assets/environment/garden_tree_willow_v2.png",
	"res://assets/environment/garden_tree_dead_v2.png"
]
const FILE_SIZES := [347410, 398019, 237892]
const TEXTURES := [Oak, Willow, Dead]

var _checks := 0
var _failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	for i in range(TEXTURES.size()):
		var art: Texture2D = TEXTURES[i]
		_check(art != null and art.get_size() == Vector2(512, 512),
			"source %d remains original 512px tree illustration" % i)
		_check(FileAccess.get_file_as_bytes(PATHS[i]).size() == FILE_SIZES[i],
			"source %d is real binary PNG, never a Git LFS stub" % i)
		var img := art.get_image()
		_check(img.get_pixel(0, 0).a < 0.05 and img.get_pixel(511, 511).a < 0.05,
			"tree %d has transparent corners, no black rectangular matte" % i)
		var tree = PaintedGardenTree.new()
		tree.art_variant = i
		tree.position = Vector2(float(128 * i), 70.0 + float(25 * i))
		root.add_child(tree)
		_check(tree.has_painted_art(), "tree %d selects Muse-painted sprite" % i)
		var sprite: Sprite2D = tree.painted_sprite()
		_check(sprite != null and sprite.texture == art,
			"tree %d uses source texture without destructive recoloring" % i)
		if sprite != null:
			var height: float = sprite.texture.get_height() * sprite.scale.y
			_check(absf(height - PaintedGardenTree.art_height(i)) < 0.5,
				"tree %d displays at sane encounter-world scale" % i)
			_check(absf(sprite.position.y + height * 0.5 - PaintedGardenTree.TRUNK_FOOT_Y) < 0.01,
				"tree %d roots align to old trunk's ground baseline" % i)
		var shape := tree.get_node_or_null("CollisionShape2D") as CollisionShape2D
		_check(shape != null and shape.shape is CircleShape2D,
			"tree %d retains round blocking trunk" % i)
		if shape != null and shape.shape is CircleShape2D:
			_check(is_equal_approx((shape.shape as CircleShape2D).radius,
				PaintedGardenTree.COLLISION_RADIUS) and shape.position == Vector2(0, 18),
				"tree %d keeps exactly original 24px trunk collision and offset" % i)
		_check(tree.collision_layer == 1 and tree.collision_mask == 0,
			"tree %d does not create new creature/terrain collision rules" % i)
		_check(tree.z_as_relative == false and tree.z_index ==
			int(round(tree.position.y + 18.0)),
			"tree %d still sorts against Mollosar's feet by world Y" % i)
		tree.queue_free()

	var observed: Dictionary = {}
	for y in range(-4, 6):
		for x in range(-5, 7):
			var p := Vector2(float(x * 64 + 32), float(y * 64 + 32))
			var one: int = PaintedGardenTree.variant_for(p, 117, 64)
			_check(one == PaintedGardenTree.variant_for(p, 117, 64),
				"tree style is deterministic and never uses RNG")
			_check(one >= 0 and one <= 2,
				"tree style stays within the three imported assets")
			observed[one] = true
	_check(observed.size() == 3,
		"garden spatial variation includes oak, willow and deadwood")

	var fixture := Garden.new()
	fixture.name = "PaintedGardenTreeFixture"
	fixture.bounds = Rect2(-448, -256, 896, 512)
	fixture.density = 0.60
	fixture.seed_value = 117
	fixture.shrine = Vector2(-250, 200)
	fixture.landmark = Vector2(200, 70)
	root.add_child(fixture)
	var trees := 0
	for child in fixture.get_children():
		if not (child is StaticBody2D and child.name == "SolidTree"):
			continue
		trees += 1
		_check(child.has_painted_art(), "spawned garden tree uses a real silhouette")
		_check(child.art_variant == PaintedGardenTree.variant_for(child.position,
			fixture.seed_value, fixture.cell_size),
			"generator assigns art without a new RNG draw")
		_check(not fixture._walkway(child.position),
			"styled tree colliders still avoid the authored walkable paths")
	_check(trees > 0 and trees == fixture.get("_trees").size(),
		"art upgrade does not add/remove any solid tree obstacles")
	fixture.queue_free()

	var fallback = PaintedGardenTree.new()
	fallback.use_painted_art = false
	root.add_child(fallback)
	_check(not fallback.has_painted_art() and fallback.get_node_or_null("CollisionShape2D") != null,
		"old procedural tree and its collision remain available as fallback")
	fallback.queue_free()

	if _failures == 0:
		print("[GARDEN PAINTED TREES] PASS %d checks" % _checks)
	else:
		push_error("[GARDEN PAINTED TREES] FAIL %d/%d" % [_failures, _checks])
	quit(1 if _failures > 0 else 0)

func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		push_error("[GARDEN PAINTED TREES] " + label)
