extends Node2D
## Visual-only weapon; combat remains in ScytheRig and WeaponData.
## Form 1 holds the mortal longsword, later reapers wield the scythe,
## and the late-game Scythe-Tail grows from living material.

const WeaponData := preload("res://scripts/weapon_data.gd")
const STEEL := Color(0.48, 0.54, 0.57)
const EDGE := Color(0.79, 0.83, 0.79)
const SHADOW := Color(0.13, 0.17, 0.20)
const SHAFT := Color(0.20, 0.17, 0.18)
const GOLD := Color(0.66, 0.54, 0.34)
const VINE := Color(0.22, 0.32, 0.18)
const GLOW := Color(0.60, 0.75, 0.39)

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
	if swinging:
		rotation = 0.0
	else:
		var facing: Vector2 = _player.get("facing")
		if facing.length_squared() < 0.01:
			facing = Vector2.DOWN
		rotation = facing.angle() - _rig.rotation
	queue_redraw()

func _form() -> int:
	if is_inside_tree():
		var state = get_node_or_null("/root/GameState")
		if state != null and state.has_method("get_form"):
			return int(state.get_form())
	return 1

func _weapon() -> String:
	if not is_inside_tree():
		return WeaponData.WEAPON_SCYTHE
	var state = get_node_or_null("/root/GameState")
	if state != null:
		return WeaponData.current_weapon(state)
	return WeaponData.WEAPON_SCYTHE

func _draw() -> void:
	if _form() <= 1:
		# Form 1's painted walk sheets already contain the longsword.
		# Show the overlaid weapon only during attacks, never two swords at idle.
		var sprite_manager = _player.get("sprites") if _player != null else null
		if sprite_manager != null and sprite_manager.has_method("has_sprites"):
			if sprite_manager.has_sprites() and int(_rig.get("state")) == 0:
				return
		_draw_mortal_sword()
	elif _weapon() == WeaponData.WEAPON_LONGSWORD:
		_draw_mortal_sword()
	elif _weapon() == WeaponData.WEAPON_SCYTHE_TAIL or _form() >= 8:
		_draw_living_tail()
	else:
		_draw_reaper_scythe()

func _draw_mortal_sword() -> void:
	# Form 1: steel longsword and gold crossguard, NEVER a reaper scythe.
	draw_line(Vector2(22, 21), Vector2(51, -9), SHAFT, 9.0, true)
	draw_circle(Vector2(20, 25), 7.0, GOLD)
	draw_line(Vector2(47, -16), Vector2(73, 7), GOLD, 8.0, true)
	var steel := PackedVector2Array([
		Vector2(49, -10), Vector2(60, -27), Vector2(127, -102),
		Vector2(144, -115), Vector2(139, -96), Vector2(74, -17)
	])
	draw_colored_polygon(steel, STEEL)
	draw_line(Vector2(54, -12), Vector2(140, -108), EDGE, 3.0, true)
	draw_line(Vector2(62, -21), Vector2(139, -108), SHADOW.lightened(0.35), 2.0, true)

func _draw_reaper_scythe() -> void:
	draw_line(Vector2(15, 23), Vector2(113, -6), SHAFT, 10.0, true)
	draw_line(Vector2(15, 21), Vector2(109, -8), SHAFT.lightened(0.25), 3.0, true)
	for t in [0.22, 0.38, 0.54, 0.70]:
		var a := Vector2(15, 23).lerp(Vector2(113, -6), t)
		draw_line(a + Vector2(-2, -6), a + Vector2(2, 5), GOLD.darkened(0.3), 3.0, true)
	draw_circle(Vector2(112, -6), 7.0, GOLD)
	var upper := PackedVector2Array([
		Vector2(104, -10), Vector2(120, -24), Vector2(132, -45),
		Vector2(137, -74), Vector2(132, -97), Vector2(120, -113),
		Vector2(144, -103), Vector2(160, -84), Vector2(169, -62),
		Vector2(168, -41), Vector2(152, -20), Vector2(124, 0)
	])
	draw_colored_polygon(upper, SHADOW)
	draw_polyline(PackedVector2Array([
		Vector2(120, -113), Vector2(144, -103),
		Vector2(160, -84), Vector2(169, -62),
		Vector2(168, -41), Vector2(152, -20), Vector2(124, 0)
	]), EDGE, 3.0, true)
	# The second curved steel head makes this Mollosar's double-headed scythe.
	var lower := PackedVector2Array([
		Vector2(113, 0), Vector2(119, 11), Vector2(116, 27),
		Vector2(101, 45), Vector2(83, 52), Vector2(95, 29),
		Vector2(99, 10)
	])
	draw_colored_polygon(lower, STEEL)
	draw_polyline(PackedVector2Array([
		Vector2(83, 52), Vector2(101, 45),
		Vector2(116, 27), Vector2(119, 11)
	]), EDGE, 2.5, true)

func _draw_living_tail() -> void:
	# Distinct plant-grown sickle for the ascended forms.
	var points := PackedVector2Array([
		Vector2(12, 22), Vector2(43, 12), Vector2(75, -12),
		Vector2(96, -46), Vector2(120, -62)
	])
	draw_polyline(points, VINE, 13.0, true)
	draw_polyline(points, GLOW.darkened(0.42), 4.0, true)
	draw_colored_polygon(PackedVector2Array([
		Vector2(116, -65), Vector2(137, -99), Vector2(162, -116),
		Vector2(157, -86), Vector2(141, -63), Vector2(121, -48)
	]), SHADOW)
	draw_polyline(PackedVector2Array([
		Vector2(162, -116), Vector2(157, -86), Vector2(141, -63)
	]), GLOW, 3.0, true)
