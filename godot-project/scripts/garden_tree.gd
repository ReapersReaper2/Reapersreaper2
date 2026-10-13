extends StaticBody2D
## Individual solid garden tree with its own canvas depth.
## Trunks sort against Mollosar's feet; crowns can obscure him naturally.

const BARK := Color(0.16, 0.13, 0.13)
const BARK_LIGHT := Color(0.29, 0.23, 0.19)
const SHADOW := Color(0.035, 0.055, 0.045, 0.42)
const FOLIAGE := Color(0.095, 0.19, 0.145)
const FOLIAGE_MID := Color(0.145, 0.275, 0.18)
const FOLIAGE_LIGHT := Color(0.23, 0.36, 0.23)

## Muse v2 transparent tree cutouts. Keep the original paintings intact;
## this script only scales/anchors them to the old trunk collision.
const OAK: Texture2D = preload("res://assets/environment/garden_tree_oak_v2.png")
const WILLOW: Texture2D = preload("res://assets/environment/garden_tree_willow_v2.png")
const DEAD_TREE: Texture2D = preload("res://assets/environment/garden_tree_dead_v2.png")
const ART_HEIGHTS := [156.0, 176.0, 154.0]
const COLLISION_RADIUS := 24.0
const TRUNK_FOOT_Y := 34.0

@export_enum("Twisted Oak", "Spirit Willow", "Deadwood") var art_variant: int = 0
@export var use_painted_art: bool = true

var _painted_sprite: Sprite2D = null

## Pick by coordinates without consuming the garden's existing seeded RNG;
## this preserves the EXACT number/location of collision trees and clearings.
static func variant_for(p: Vector2, garden_seed: int, cell: int = 64) -> int:
	var gx := int(floor(p.x / float(maxi(cell, 1))))
	var gy := int(floor(p.y / float(maxi(cell, 1))))
	return posmod(gx * 17 + gy * 29 + garden_seed * 7, 3)

static func art_height(style: int) -> float:
	return ART_HEIGHTS[clampi(style, 0, 2)]

func _selected_texture() -> Texture2D:
	match art_variant:
		1:
			return WILLOW
		2:
			return DEAD_TREE
		_:
			return OAK

func _create_painted_art() -> void:
	if not use_painted_art:
		return
	var tex := _selected_texture()
	if tex == null or tex.get_height() <= 0:
		push_warning("[GardenTree] Tree painting unavailable; drawing old canopy")
		return
	var art := Sprite2D.new()
	art.name = "PaintedTree"
	art.texture = tex
	art.centered = true
	var h := art_height(art_variant)
	var ratio := h / float(tex.get_height())
	art.scale = Vector2(ratio, ratio)
	art.position = Vector2(0.0, TRUNK_FOOT_Y - h * 0.5)
	art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	add_child(art)
	_painted_sprite = art

func has_painted_art() -> bool:
	return _painted_sprite != null

func painted_sprite() -> Sprite2D:
	return _painted_sprite

func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	z_as_relative = false
	z_index = clampi(int(round(position.y + 18.0)), -1900, 1900)
	var collider := CollisionShape2D.new()
	var trunk := CircleShape2D.new()
	trunk.radius = COLLISION_RADIUS
	collider.shape = trunk
	collider.position = Vector2(0, 18)
	add_child(collider)
	_create_painted_art()
	queue_redraw()

func _draw() -> void:
	# The old collision foot casts a ground shadow even when the painted
	# tree sways visually over the player. Color shapes are fallback only.
	draw_circle(Vector2(11, 25), 30.0, SHADOW)
	if has_painted_art():
		return
	# Procedural backup if Muse artwork is unavailable or toggled off.
	draw_line(Vector2(0, 26), Vector2(0, -34), BARK, 18.0, true)
	draw_line(Vector2(-23, 23), Vector2(0, 13), BARK, 9.0, true)
	draw_line(Vector2(23, 23), Vector2(0, 13), BARK, 9.0, true)
	draw_line(Vector2(-4, 11), Vector2(-4, -31), BARK_LIGHT, 2.0, true)
	draw_circle(Vector2(0, -47), 46.0, FOLIAGE)
	draw_circle(Vector2(-24, -58), 31.0, FOLIAGE_MID)
	draw_circle(Vector2(21, -72), 32.0, FOLIAGE)
	draw_circle(Vector2(-8, -85), 24.0, FOLIAGE_LIGHT)
	draw_circle(Vector2(-28, -64), 9.0, FOLIAGE_LIGHT.darkened(0.20))
