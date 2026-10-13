extends Node2D
## Bellhollow Bridge: weathered, organic stone flagging, damaged rails,
## ash and ember wear. The approved painted city panorama remains untouched.
## This is a presentation-only replacement for the hard rectangular grid;
## original collision boundaries, room dimensions and story path remain.
##
## Geometry is deterministic and generated once at _draw(), not per frame.
@export var bounds: Rect2 = Rect2(-1280, -360, 2560, 720)

const FOUNDATION := Color(0.126, 0.125, 0.139)
const MORTAR := Color(0.111, 0.113, 0.121)
const BASALT := Color(0.23, 0.224, 0.221)
const OXIDIZED := Color(0.318, 0.294, 0.263)
const WET_EDGE := Color(0.38, 0.341, 0.308)
const ASH := Color(0.10, 0.109, 0.119)
const ASH_HAZE := Color(0.30, 0.27, 0.252)
const EMBER := Color(0.91, 0.39, 0.17)
const SEAM := Color(0.15, 0.14, 0.149)

func _ready() -> void:
	z_index = -1
	queue_redraw()


## Each stone is irregular and uniquely weathered; no right-angled
## uniform grid tiles. Stable seed ensures the same bridge on every load.
static func flagstones_for(area: Rect2) -> Array:
	var stones: Array = []
	if area.size.x <= 0.0:
		return stones
	var rng := RandomNumberGenerator.new()
	rng.seed = 71011
	var left := area.position.x
	var right := area.end.x
	for course in range(6):
		var top := -100.0 + float(course) * 65.0
		var bottom := top + 67.0
		var x := left - (rng.randf_range(16.0, 160.0))
		while x < right:
			var w := rng.randf_range(113.0, 245.0)
			var rough_left := rng.randf_range(6.0, 16.0)
			var rough_right := rng.randf_range(7.0, 18.0)
			var rough_top := rng.randf_range(3.0, 8.0)
			var rough_bottom := rng.randf_range(3.0, 8.0)
			var vertices := PackedVector2Array([
				Vector2(x + rough_left, top + rough_top),
				Vector2(x + w * 0.35, top + rng.randf_range(1.0, 5.0)),
				Vector2(x + w - rough_right, top + rng.randf_range(4.0, 9.0)),
				Vector2(x + w - rng.randf_range(2.0, 9.0), top + 24.0),
				Vector2(x + w - rough_right * 0.7, bottom - rough_bottom),
				Vector2(x + w * 0.43, bottom - rng.randf_range(3.0, 8.0)),
				Vector2(x + rough_left, bottom - rough_bottom * 0.8),
				Vector2(x + rng.randf_range(3.0, 10.0), top + 27.0),
			])
			stones.append({
				"polygon": vertices,
				"shade": rng.randf_range(0.0, 1.0),
				"patina": rng.randf_range(0.0, 1.0),
				"fractured": rng.randf() < 0.17,
			})
			x += w + rng.randf_range(2.0, 11.0)
	return stones


func _draw() -> void:
	var l := bounds.position.x
	var r := bounds.end.x
	# Continuous dark foundation prevents pixel-gaps between rounded stone
	# contours from revealing the city's background through the road.
	draw_rect(Rect2(l, -112.0, bounds.size.x, 412.0), FOUNDATION)
	draw_rect(Rect2(l, -100.0, bounds.size.x, 393.0), MORTAR)
	for stone_value in flagstones_for(bounds):
		var stone: Dictionary = stone_value
		var vertices: PackedVector2Array = stone["polygon"]
		var warm := float(stone["patina"])
		var base := BASALT.lerp(OXIDIZED, 0.16 + warm * 0.34)
		var shade := float(stone["shade"])
		base = base.lightened(shade * 0.06).darkened((1.0 - shade) * 0.07)
		draw_colored_polygon(vertices, base)
		# Small broken edge glints rather than rectangular stroke outlines.
		var rim := WET_EDGE
		rim.a = 0.22 + 0.16 * shade
		draw_line(vertices[0] + Vector2(9, 3), vertices[1] - Vector2(7, 0), rim, 1.5, true)
		draw_line(vertices[1] + Vector2(9, 0), vertices[2] - Vector2(6, 0), rim, 1.0, true)
		if bool(stone["fractured"]):
			var center := vertices[0].lerp(vertices[4], 0.46)
			draw_line(center - Vector2(18, 14), center + Vector2(2, 3), SEAM, 1.8, true)
			draw_line(center + Vector2(2, 3), center + Vector2(-6, 24), SEAM, 1.25, true)

	_draw_weathering()
	_draw_parapet(l, r, -145.0, true)
	_draw_parapet(l, r, 308.0, false)
	_draw_rubble()


func _draw_parapet(left: float, right: float, y: float, far_edge: bool) -> void:
	var p := PackedVector2Array([
		Vector2(left, y - 21), Vector2(left + 67, y - 27),
		Vector2(left + 300, y - 23), Vector2(left + 650, y - 28),
		Vector2(right - 250, y - 20), Vector2(right, y - 25),
		Vector2(right, y + 23), Vector2(left, y + 23),
	])
	draw_colored_polygon(p, ASH)
	draw_line(Vector2(left, y - 20), Vector2(right, y - 20),
		WET_EDGE.darkened(0.13), 2.6, true)
	draw_line(Vector2(left, y + 19), Vector2(right, y + 19),
		Color(0.09, 0.094, 0.105, 0.75), 4.2, true)

	var rng := RandomNumberGenerator.new()
	rng.seed = 808 if far_edge else 909
	var post_x := left + 84.0
	while post_x < right - 35.0:
		var spread := rng.randf_range(174.0, 266.0)
		var chipped := rng.randf() < 0.38
		_draw_worn_post(Vector2(post_x, y), chipped, far_edge)
		post_x += spread
	# Asymmetrical fracture segments run across a few old parapet joints.
	for i in range(10):
		var fx := left + float(i) * (right - left) / 10.0 + 23.0
		var crack := Color(0.09, 0.09, 0.10, 0.65)
		draw_line(Vector2(fx, y - 20), Vector2(fx - 5.0, y - 3), crack, 1.5, true)
		draw_line(Vector2(fx - 5.0, y - 3), Vector2(fx + 2.0, y + 17), crack, 1.0, true)


func _draw_worn_post(p: Vector2, broken: bool, far_edge: bool) -> void:
	var top_y := -34.0 if far_edge else -28.0
	var notch := 10.0 if broken else 0.0
	var silhouette := PackedVector2Array([
		p + Vector2(-11, 18), p + Vector2(-15, top_y + 8),
		p + Vector2(-9, top_y - 7 + notch), p + Vector2(5, top_y - 10 + notch),
		p + Vector2(14, top_y + 2), p + Vector2(12, 19),
	])
	draw_colored_polygon(silhouette, ASH)
	var cap := PackedVector2Array([
		p + Vector2(-19, top_y - 3 + notch),
		p + Vector2(-10, top_y - 9 + notch),
		p + Vector2(12, top_y - 6 + notch),
		p + Vector2(18, top_y + 1),
		p + Vector2(4, top_y + 7),
		p + Vector2(-18, top_y + 6),
	])
	draw_colored_polygon(cap, BASALT.lerp(OXIDIZED, 0.24))
	draw_line(p + Vector2(-12, top_y + 6), p + Vector2(-10, 12),
		WET_EDGE.darkened(0.45), 1.7, true)
	if broken:
		draw_line(p + Vector2(-5, top_y + 1 + notch), p + Vector2(1, top_y + 7),
			ASH_HAZE, 1.2, true)


func _draw_weathering() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 47001
	for i in range(250):
		var p := Vector2(rng.randf_range(bounds.position.x, bounds.end.x),
			rng.randf_range(-91.0, 286.0))
		var length := rng.randf_range(4.0, 18.0)
		var accent := ASH_HAZE if rng.randf() < 0.32 else SEAM
		accent.a = rng.randf_range(0.07, 0.26)
		draw_line(p, p + Vector2(length, -length * rng.randf_range(0.1, 0.45)),
			accent, rng.randf_range(0.75, 1.8), true)
	for i in range(37):
		var p := Vector2(rng.randf_range(bounds.position.x, bounds.end.x),
			rng.randf_range(-65.0, 271.0))
		var c := EMBER
		c.a = rng.randf_range(0.2, 0.58)
		draw_circle(p, rng.randf_range(0.6, 1.6), c)


func _draw_rubble() -> void:
	# Ruin debris at the edges only; the central sword-fighting corridor
	# and triggering volumes remain visually open and collision-free.
	var rng := RandomNumberGenerator.new()
	rng.seed = 21907
	for x in [-1035.0, -460.0, 380.0, 960.0]:
		for i in range(7):
			var offset := Vector2(rng.randf_range(-56, 56), rng.randf_range(-13, 15))
			var p := Vector2(x, -96.0) + offset
			var rubble := PackedVector2Array([
				p + Vector2(-12, 6), p + Vector2(-7, -7),
				p + Vector2(6, -14), p + Vector2(14, 3), p + Vector2(2, 9),
			])
			draw_colored_polygon(rubble, ASH.lerp(BASALT, rng.randf_range(0.25, 0.64)))
