extends StaticBody2D
## Solid depth-sorted garden tree, now using approved transparent Muse art.
## All original trunk collisions and tree positions stay exactly the same.
## Fallback procedural geometry remains available if art is disabled.

const TREE_ART := [
	preload("res://assets/environment/garden_tree_twisted_oak_v2.png"),
	preload("res://assets/environment/garden_tree_willow_v2.png"),
	preload("res://assets/environment/garden_tree_dead_v2.png"),
	preload("res://assets/environment/garden_tree_bonewhite_v1.png"),
]
## Source alpha bounding boxes: oak/willow/dead are broadly grounded at
## y=489, bone-white at y=412. Maintain a shared world-space root baseline.
const ART_ALPHA_BOTTOM := [489.0, 489.0, 490.0, 412.0]
const ART_ALPHA_HEIGHT := [466.0, 466.0, 467.0, 321.0]
const DISPLAY_HEIGHT := [175.0, 177.0, 166.0, 155.0]

const BARK := Color(0.16, 0.13, 0.13)
const BARK_LIGHT := Color(0.29, 0.23, 0.19)
const SHADOW := Color(0.035, 0.055, 0.045, 0.42)
const FOLIAGE := Color(0.095, 0.19, 0.145)
const FOLIAGE_MID := Color(0.145, 0.275, 0.18)
const FOLIAGE_LIGHT := Color(0.23, 0.36, 0.23)

@export_range(0, 3, 1) var tree_variant: int = 0
@export var use_painted_tree: bool = true
var _painted_sprite: Sprite2D = null

## An independent hash of authored coordinates avoids consuming the layout
## RNG. Upgrading the art cannot move a tree, rock, shrub or walking route.
static func variant_for_position(p: Vector2, world_seed: int) -> int:
	var x := int(round(p.x))
	var y := int(round(p.y))
	var roll := posmod(x * 73 + y * 19 + world_seed * 31, 100)
	if roll < 45:
		return 0 # Twisted oak
	if roll < 73:
		return 1 # Dreamlike willow
	if roll < 94:
		return 2 # Ancient leafless tree
	return 3 # Rare pale bone-white tree


func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	z_as_relative = false
	z_index = clampi(int(round(position.y + 18.0)), -1900, 1900)
	var collider := CollisionShape2D.new()
	collider.name = "TrunkCollision"
	var trunk := CircleShape2D.new()
	trunk.radius = 24.0
	collider.shape = trunk
	collider.position = Vector2(0, 18)
	add_child(collider)
	if use_painted_tree:
		_build_painted_tree()
	queue_redraw()


func _build_painted_tree() -> void:
	var index := clampi(tree_variant, 0, TREE_ART.size() - 1)
	var source: Texture2D = TREE_ART[index]
	if source == null or source.get_width() <= 0:
		push_warning("[GardenTree] Approved PNG unavailable; keeping procedural tree")
		return
	var scale_factor: float = DISPLAY_HEIGHT[index] / ART_ALPHA_HEIGHT[index]
	var sprite := Sprite2D.new()
	sprite.name = "PaintedTreeArt"
	sprite.texture = source
	sprite.scale = Vector2.ONE * scale_factor
	# The bottommost opaque pixels sit on the SAME physical trunk centre
	# used by the original collider, even for bone-white art with padding.
	sprite.position = Vector2(0.0,
		18.0 - (ART_ALPHA_BOTTOM[index] - float(source.get_height()) / 2.0)
		* scale_factor)
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	add_child(sprite)
	_painted_sprite = sprite


func has_painted_tree() -> bool:
	return _painted_sprite != null


func get_visual_foot_y() -> float:
	if _painted_sprite == null:
		return 18.0
	var index := clampi(tree_variant, 0, ART_ALPHA_BOTTOM.size() - 1)
	return _painted_sprite.position.y + (
		ART_ALPHA_BOTTOM[index] - float(_painted_sprite.texture.get_height()) / 2.0
	) * _painted_sprite.scale.y


func _draw() -> void:
	# Fixed shadow and trunk footprint prevent the tree from feeling like a
	# floating illustration on the newly painted grass/soil shader.
	draw_circle(Vector2(11, 25), 30.0, SHADOW)
	if _painted_sprite != null:
		return
	# Safe procedural fallback (no LFS dependency, no lost collision).
	draw_line(Vector2(0, 26), Vector2(0, -34), BARK, 18.0, true)
	draw_line(Vector2(-23, 23), Vector2(0, 13), BARK, 9.0, true)
	draw_line(Vector2(23, 23), Vector2(0, 13), BARK, 9.0, true)
	draw_line(Vector2(-4, 11), Vector2(-4, -31), BARK_LIGHT, 2.0, true)
	draw_circle(Vector2(0, -47), 46.0, FOLIAGE)
	draw_circle(Vector2(-24, -58), 31.0, FOLIAGE_MID)
	draw_circle(Vector2(21, -72), 32.0, FOLIAGE)
	draw_circle(Vector2(-8, -85), 24.0, FOLIAGE_LIGHT)
	draw_circle(Vector2(-28, -64), 9.0, FOLIAGE_LIGHT.darkened(0.20))
