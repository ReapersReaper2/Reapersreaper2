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

const GardenTree := preload("res://scripts/garden_tree.gd")

@export var feature_points: PackedVector2Array = PackedVector2Array()

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
	# Ground below all actors; individual tree canopies use absolute Z.
	z_index = -2000
	_generate()
	queue_redraw()

func _process(_delta: float) -> void:
	# Avoid editing existing player / companion movement scripts.
	for actor_name in ["Player", "Luna", "Ivy", "ShrineGd1", "ShrineGd2",
			"ShrineGd3", "GardenPerimeter", "WrathsJournal",
			"IvySanctum", "AncientVine", "TakeCutting"]:
		var actor := get_parent().get_node_or_null(actor_name) as Node2D
		if actor != null:
			actor.z_index = clampi(int(round(actor.position.y + 18.0)), -1900, 1900)
	var creatures := get_parent().get_node_or_null("Creatures")
	if creatures != null:
		for creature in creatures.get_children():
			if creature is Node2D:
				creature.z_as_relative = false
				creature.z_index = clampi(int(round(creature.global_position.y)), -1900, 1900)
	var hut := get_parent().get_node_or_null("GardenRefugeCottage") as Node2D
	if hut != null:
		hut.z_index = clampi(int(round(hut.position.y + 70.0)), -1900, 1900)

func _route_y(x: float) -> float:
	return 100.0 + sin(x * 0.004 + float(seed_value)) * 44.0

func _walkway(p: Vector2) -> bool:
	# The east-west trail connects both pre-existing exit triggers.
	if absf(p.y - _route_y(p.x)) < 110.0:
		return true
	# A northern loop gives the room optional exploration beyond the main road.
	var loop_y := -185.0 + sin(p.x * 0.005) * 35.0
	if absf(p.y - loop_y) < 58.0 and absf(p.x - bounds.get_center().x) < bounds.size.x * 0.39:
		return true
	# Every key story location gets an obstacle-free clearing AND a branch
	# to the primary trail. This also keeps the cottage doorway reachable.
	var destinations := PackedVector2Array([shrine, landmark])
	destinations.append_array(feature_points)
	for destination in destinations:
		if p.distance_to(destination) < 155.0:
			return true
		var trail := Vector2(destination.x, _route_y(destination.x))
		if _distance_to_segment(p, destination, trail) < 75.0:
			return true
	return false


static func _distance_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var edge := b - a
	var length_sq := edge.length_squared()
	if length_sq < 0.001:
		return p.distance_to(a)
	var t := clampf((p - a).dot(edge) / length_sq, 0.0, 1.0)
	return p.distance_to(a + edge * t)

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
	var tree := GardenTree.new()
	tree.name = "SolidTree"
	tree.position = p
	add_child(tree)

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
	# Tree canopies are their own canvas items, depth-sorted with the player.
	# A navigational focal point at the garden entrance.
	draw_arc(landmark, 72.0, 0, TAU, 32, STONE, 9.0)
	draw_line(landmark + Vector2(-32, -50), landmark + Vector2(-32, 26), STONE, 10.0)
	draw_line(landmark + Vector2(32, -50), landmark + Vector2(32, 26), STONE, 10.0)
	draw_arc(landmark + Vector2(0, -45), 32, PI, TAU, 16, STONE.lightened(0.2), 8)
	_draw_gate(Vector2(bounds.position.x + 70.0, 100.0))
	_draw_gate(Vector2(bounds.end.x - 70.0, 100.0))

func _draw_gate(p: Vector2) -> void:
	# Framed trail opening at each existing exit trigger.
	var dark := STONE.darkened(0.38)
	draw_rect(Rect2(p + Vector2(-58, -92), Vector2(19, 130)), dark)
	draw_rect(Rect2(p + Vector2(39, -92), Vector2(19, 130)), dark)
	draw_rect(Rect2(p + Vector2(-58, -105), Vector2(116, 23)), STONE)
	draw_rect(Rect2(p + Vector2(-48, -100), Vector2(96, 7)), STONE.lightened(0.23))
	for dx in [-50.0, 49.0]:
		draw_circle(p + Vector2(dx, 36), 15.0, MOSS)
	# A warm threshold signals traversability without extra collision.
	draw_line(p + Vector2(-35, 34), p + Vector2(35, 34), GOLD_GATE(), 5.0)

func GOLD_GATE() -> Color:
	return Color(0.57, 0.42, 0.24, 0.85)
