extends Node2D
## Playable, cell-based garden landscape. Replaces a flat backdrop with
## authored routes, clearings, solid trees, ruins and ground variation.
## Reusable across garden rooms; no imported textures required.
@export var bounds: Rect2 = Rect2(-1280, -360, 2560, 720)
@export var cell_size: int = 64
@export var seed_value: int = 117
@export var density: float = 0.46
@export var landmark: Vector2 = Vector2(300, 100)
@export var shrine: Vector2 = Vector2(-1000, 200)

const SOIL := Color(0.115, 0.155, 0.133)
const SOIL_2 := Color(0.14, 0.19, 0.155)
const PATH := Color(0.29, 0.255, 0.205)
const PATH_LIGHT := Color(0.35, 0.30, 0.22)
const MOSS := Color(0.23, 0.30, 0.21)
const LEAF := Color(0.12, 0.23, 0.175)
const LEAF_LIGHT := Color(0.20, 0.33, 0.22)
const TRUNK := Color(0.18, 0.15, 0.15)
const STONE := Color(0.33, 0.33, 0.32)
var _trees: Array[Vector2] = []
var _rocks: Array[Vector2] = []
var _tufts: Array[Vector2] = []

func _ready() -> void:
	_generate()
	queue_redraw()

func _route_y(x: float) -> float:
	return 100.0 + sin(x * 0.004 + float(seed_value)) * 44.0

func _walkway(p: Vector2) -> bool:
	# A broad east-west spine guarantees both room exits are reachable.
	if absf(p.y - _route_y(p.x)) < 105.0:
		return true
	# A looping secondary garden walk plus branches to the shrine and gate.
	var loop_y := -185.0 + sin(p.x * 0.005) * 35.0
	if absf(p.y - loop_y) < 58.0 and absf(p.x) < bounds.size.x * 0.39:
		return true
	if absf(p.x - landmark.x) < 90.0 and p.y > -220.0 and p.y < 210.0:
		return true
	if p.x > 0.0 and p.x < 450.0 and absf(p.y + 100.0) < 70.0:
		return true
	if absf(p.x - shrine.x) < 95.0 and p.y > -220.0:
		return true
	for place in [landmark, shrine, Vector2.ZERO]:
		if p.distance_to(place) < 156.0:
			return true
	return false

func _generate() -> void:
	_trees.clear()
	_rocks.clear()
	_tufts.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var cols := int(ceilf(bounds.size.x / float(cell_size)))
	var rows := int(ceilf(bounds.size.y / float(cell_size)))
	for y in range(rows):
		for x in range(cols):
			var p := bounds.position + Vector2((x + 0.5) * cell_size, (y + 0.5) * cell_size)
			if _walkway(p):
				if rng.randf() < 0.14:
					_tufts.append(p + Vector2(rng.randf_range(-12, 12), rng.randf_range(-12, 12)))
				continue
			var chance := rng.randf()
			if chance < density:
				_trees.append(p)
				_add_tree_collider(p)
			elif chance < density + 0.09:
				_rocks.append(p)
			elif chance < density + 0.30:
				_tufts.append(p)

func _add_tree_collider(p: Vector2) -> void:
	# The canopy is visual, only the trunk/roots prevent walking.
	var body := StaticBody2D.new()
	body.name = "SolidTree"
	body.position = p
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 24.0
	shape.shape = circle
	shape.position = Vector2(0, 18)
	body.add_child(shape)
	add_child(body)

func _draw() -> void:
	draw_rect(bounds, SOIL)
	var cols := int(ceilf(bounds.size.x / float(cell_size)))
	var rows := int(ceilf(bounds.size.y / float(cell_size)))
	for y in range(rows):
		for x in range(cols):
			var p := bounds.position + Vector2((x + 0.5) * cell_size, (y + 0.5) * cell_size)
			var tile := Rect2(p - Vector2.ONE * cell_size * 0.5, Vector2.ONE * cell_size)
			var v := sin(float(x * 37 + y * 73 + seed_value) * 1.7)
			if _walkway(p):
				draw_rect(tile, PATH if v < 0.45 else PATH_LIGHT)
				if v > 0.3:
					draw_circle(p + Vector2(13, -10), 3.0, STONE.darkened(0.25))
			else:
				draw_rect(tile, SOIL if v < 0.1 else SOIL_2)
				draw_circle(p + Vector2(-17, 16), 11.0, MOSS.darkened(0.22))
	for p in _tufts:
		draw_line(p + Vector2(-7, 7), p + Vector2(-2, -7), LEAF_LIGHT, 3.0)
		draw_line(p + Vector2(2, 8), p + Vector2(8, -5), LEAF, 3.0)
	for p in _rocks:
		draw_colored_polygon(PackedVector2Array([p + Vector2(-25, 14), p + Vector2(-13, -16), p + Vector2(13, -22), p + Vector2(26, 12)]), STONE)
		draw_line(p + Vector2(-13, -13), p + Vector2(12, -19), STONE.lightened(0.25), 3.0)
	# Grove silhouettes: broad, overlapping canopies and visible root bases.
	for p in _trees:
		draw_ellipse_tree(p)
	# A navigational focal point at the garden entrance.
	draw_arc(landmark, 72.0, 0, TAU, 32, STONE, 9.0)
	draw_line(landmark + Vector2(-32, -50), landmark + Vector2(-32, 26), STONE, 10.0)
	draw_line(landmark + Vector2(32, -50), landmark + Vector2(32, 26), STONE, 10.0)
	draw_arc(landmark + Vector2(0, -45), 32, PI, TAU, 16, STONE.lightened(0.2), 8)

func draw_ellipse_tree(p: Vector2) -> void:
	draw_circle(p + Vector2(8, 24), 32, Color(0.03, 0.05, 0.045, 0.45))
	draw_line(p + Vector2(0, 23), p + Vector2(0, -31), TRUNK, 17)
	draw_line(p + Vector2(-17, 23), p + Vector2(0, 12), TRUNK, 8)
	draw_line(p + Vector2(17, 21), p + Vector2(0, 12), TRUNK, 8)
	draw_circle(p + Vector2(0, -45), 45, LEAF)
	draw_circle(p + Vector2(-23, -57), 31, LEAF_LIGHT.darkened(0.18))
	draw_circle(p + Vector2(20, -69), 33, LEAF)
	draw_circle(p + Vector2(-9, -82), 25, LEAF_LIGHT)
