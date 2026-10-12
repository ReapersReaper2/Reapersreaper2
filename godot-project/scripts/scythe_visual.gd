extends Node2D
## Painterly, resolution-independent scythe silhouette.
## The ScytheRig remains responsible for combat; this child is visual only.
## No texture import or LFS dependency is required.

const STEEL := Color(0.48, 0.54, 0.57)
const EDGE := Color(0.79, 0.83, 0.79)
const SHADOW := Color(0.13, 0.17, 0.20)
const SHAFT := Color(0.20, 0.17, 0.18)
const GOLD := Color(0.66, 0.54, 0.34)

var _rig: Node2D
var _player: Node2D


func _ready() -> void:
	_rig = get_parent() as Node2D
	if _rig != null:
		_player = _rig.get_parent() as Node2D
	z_index = 4


func _process(_delta: float) -> void:
	if _rig == null or _player == null:
		return
	var swinging := int(_rig.get("state")) != 0
	# Combat rotates the rig to the locked attack direction. When idle,
	# counteract its stale rotation and follow Mollosar's current facing.
	if swinging:
		rotation = 0.0
	else:
		var facing: Vector2 = _player.get("facing")
		if facing.length_squared() < 0.01:
			facing = Vector2.DOWN
		rotation = facing.angle() - _rig.rotation
	queue_redraw()


func _draw() -> void:
	# Tangled dark-wood grip, bound with a warm metal ferrule.
	draw_line(Vector2(15, 23), Vector2(113, -6), SHAFT, 10.0, true)
	draw_line(Vector2(15, 21), Vector2(109, -8), Color(0.38, 0.31, 0.29), 3.0, true)
	for t in [0.22, 0.38, 0.54, 0.70]:
		var a := Vector2(15, 23).lerp(Vector2(113, -6), t)
		draw_line(a + Vector2(-2, -6), a + Vector2(2, 5), GOLD.darkened(0.30), 3.0, true)
	draw_circle(Vector2(112, -6), 7.0, GOLD)
	# Asymmetric hooked iron: dark back, cold cutting edge.
	var blade := PackedVector2Array([
		Vector2(104, -10), Vector2(120, -24), Vector2(132, -45),
		Vector2(137, -74), Vector2(132, -97), Vector2(120, -113),
		Vector2(144, -103), Vector2(160, -84), Vector2(169, -62),
		Vector2(168, -41), Vector2(152, -20), Vector2(124, 0)
	])
	draw_colored_polygon(blade, SHADOW)
	draw_polyline(PackedVector2Array([
		Vector2(120, -113), Vector2(144, -103),
		Vector2(160, -84), Vector2(169, -62),
		Vector2(168, -41), Vector2(152, -20),
		Vector2(124, 0)
	]), EDGE, 3.0, true)
	draw_polyline(PackedVector2Array([
		Vector2(109, -11), Vector2(128, -30),
		Vector2(137, -53), Vector2(139, -79)
	]), STEEL, 5.0, true)
	draw_line(Vector2(117, -7), Vector2(151, -38), GOLD.darkened(0.35), 2.0, true)
