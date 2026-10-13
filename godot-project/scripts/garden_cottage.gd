extends Node2D
## Walk-in refuge facade. Place on a roadside clearing and pair with an Area2D entrance.
## Uses the approved transparent Muse building-cottage-v2.png while preserving
## the door's authored local (0, 64) threshold and existing collisions.
const PAINTED_COTTAGE: Texture2D = preload(
	"res://assets/environment/garden_refuge_cottage_v2.png")
@export var use_painted_facade: bool = true
const COTTAGE_SCALE := 0.64
const COTTAGE_TOP := -143.0
## Source image has 512x341 pixels and an alpha bbox ending at y=327.
const COTTAGE_VISIBLE_BOTTOM := 327.0
var _painted_facade: Sprite2D = null

func _ready() -> void:
	if use_painted_facade and PAINTED_COTTAGE != null:
		var art := Sprite2D.new()
		art.name = "PaintedCottageFacade"
		art.texture = PAINTED_COTTAGE
		art.centered = false
		art.scale = Vector2.ONE * COTTAGE_SCALE
		art.position = Vector2(-PAINTED_COTTAGE.get_width() * COTTAGE_SCALE * 0.5,
			COTTAGE_TOP)
		art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		add_child(art)
		_painted_facade = art
	queue_redraw()

func has_painted_facade() -> bool:
	return _painted_facade != null

func get_doorstep_y() -> float:
	if _painted_facade == null:
		return 64.0
	return _painted_facade.position.y + COTTAGE_VISIBLE_BOTTOM * _painted_facade.scale.y

const STONE := Color(0.31, 0.31, 0.30)
const DARK := Color(0.12, 0.14, 0.145)
const ROOF := Color(0.17, 0.22, 0.19)
const TRIM := Color(0.48, 0.40, 0.28)
const LIGHT := Color(0.86, 0.60, 0.27)

func _draw() -> void:
	if has_painted_facade():
		# Native painted facade entirely replaces provisional blocks.
		# Collider and exit Area2D remain in room_gd1.tscn.
		return
	# The door is at local (0, 64), allowing the player to approach from below.
	draw_rect(Rect2(-92, -64, 184, 134), DARK)
	draw_rect(Rect2(-83, -57, 166, 115), STONE)
	for i in range(6):
		var by := -43.0 + i * 18.0
		draw_line(Vector2(-80, by), Vector2(80, by), DARK, 2)
	draw_colored_polygon(PackedVector2Array([
		Vector2(-117, -57), Vector2(0, -133), Vector2(117, -57),
		Vector2(104, -35), Vector2(0, -109), Vector2(-104, -35)
	]), ROOF)
	draw_line(Vector2(-110, -56), Vector2(0, -126), TRIM, 5)
	draw_line(Vector2(0, -126), Vector2(110, -56), TRIM, 5)
	draw_rect(Rect2(-26, 1, 52, 68), DARK)
	draw_rect(Rect2(-22, 7, 44, 63), Color(0.035, 0.052, 0.049))
	draw_rect(Rect2(-32, 0, 8, 72), TRIM)
	draw_rect(Rect2(24, 0, 8, 72), TRIM)
	draw_rect(Rect2(-34, -8, 68, 9), TRIM)
	for px in [-60.0, 60.0]:
		draw_rect(Rect2(px - 10, -4, 20, 24), DARK)
		draw_rect(Rect2(px - 7, -1, 14, 17), LIGHT)
		draw_line(Vector2(px, -1), Vector2(px, 16), DARK, 3)
	draw_line(Vector2(-22, 72), Vector2(22, 72), LIGHT, 3)
