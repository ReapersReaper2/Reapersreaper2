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
var _last_attack_index: int = 1

func _ready() -> void:
	_rig = get_parent() as Node2D
	if _rig != null:
		_player = _rig.get_parent() as Node2D
		if _rig.has_signal("swing_started"):
			_rig.connect("swing_started", Callable(self, "_on_swing_started"))
	z_index = 4


func _on_swing_started(index: int) -> void:
	_last_attack_index = index

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

## A populated painted character strip owns all visible weapons.
static func should_draw_external_weapon(has_painted_character: bool) -> bool:
	return not has_painted_character


func _draw() -> void:
	# Painted Mollosar already carries his weapon. Movement/strike must
	# happen within that character art, never as an external sword/scythe
	# orbiting around him. Use this procedural rig ONLY for greybox fallback.
	var painted_manager = _player.get("sprites") if _player != null else null
	if painted_manager != null and painted_manager.has_method("has_sprites"):
		if not should_draw_external_weapon(painted_manager.has_sprites()):
			return
	if _form() <= 1:
		# Form 1's painted walk sheets already contain the longsword.
		# Show the overlaid weapon only during attacks, never two swords at idle.
		var sprite_manager = _player.get("sprites") if _player != null else null
		if sprite_manager != null and sprite_manager.has_method("uses_painted_mortal_blade"):
			if sprite_manager.uses_painted_mortal_blade():
				# Muse's actual blade is separated and animated by the sprite
				# manager. Never draw a SECOND weapon on his other hand.
				return
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

## The mortal sword uses a short, shoulder-driven slash, not a giant
## rotating scythe mesh. All angles are in radians relative to the facing
## direction of ScytheRig. The second combo hit travels back across.
static func sword_stroke_angle(index: int, fraction: float) -> float:
	var p := clampf(fraction, 0.0, 1.0)
	var angle := 0.0
	if p < 0.19:
		var u := p / 0.19
		angle = lerpf(0.0, -1.22, u * u * (3.0 - 2.0 * u))
	elif p < 0.67:
		var u := (p - 0.19) / 0.48
		# Quick acceleration, a clean middle-strike, then follow-through.
		var snap := 1.0 - pow(1.0 - u, 2.25)
		angle = lerpf(-1.22, 1.05, snap)
	else:
		var u := (p - 0.67) / 0.33
		angle = lerpf(1.05, 0.0, u * u * (3.0 - 2.0 * u))
	return -angle if index == 2 else angle


static func sword_trail_opacity(fraction: float) -> float:
	var p := clampf(fraction, 0.0, 1.0)
	if p <= 0.24 or p >= 0.78:
		return 0.0
	return sin(PI * (p - 0.24) / 0.54) * 0.50


func _draw_mortal_sword() -> void:
	# The player art already holds a resting blade. Only animate an overlay
	# in motion, with its grip in reach of the hands and realistic ~90px tip.
	var attack_state := int(_rig.get("state")) if _rig != null else 0
	var swing_index := attack_state if attack_state in [1, 2] else _last_attack_index
	var fraction := 0.0
	if _rig != null and attack_state >= 1 and attack_state <= 2:
		var duration := maxf(0.001, float(_rig.call("_swing_duration")))
		fraction = clampf(float(_rig.get("_swing_t")) / duration, 0.0, 1.0)
	elif attack_state == 3:
		fraction = 1.0
	# The sword belongs in the hands, not at the tip of a 144px triangle.
	var grip := Vector2(6.0, -31.0)
	var angle := sword_stroke_angle(swing_index, fraction) if attack_state != 0 else -0.35
	var trail_alpha := sword_trail_opacity(fraction) if attack_state in [1, 2] else 0.0
	if trail_alpha > 0.0:
		# A thin steel glint traces the arc briefly; no big neon sector.
		var glint := Color(0.86, 0.88, 0.79, trail_alpha)
		draw_arc(grip, 82.0, angle - 0.26, angle + 0.08, 12, glint, 2.5, true)
		var echo := Color(0.54, 0.64, 0.62, trail_alpha * 0.40)
		draw_arc(grip, 77.0, angle - 0.41, angle - 0.14, 12, echo, 4.0, true)
	draw_set_transform(grip, angle, Vector2.ONE)
	# Dark grip / gold crossguard; tapered double-edged weathered steel.
	draw_line(Vector2(-14, 0), Vector2(22, 0), SHAFT, 6.0, true)
	draw_circle(Vector2(-14, 0), 5.0, GOLD.darkened(0.28))
	draw_line(Vector2(20, -11), Vector2(20, 11), GOLD, 5.0, true)
	draw_circle(Vector2(20, 0), 3.5, SHADOW)
	var metal := PackedVector2Array([
		Vector2(22, -5.5), Vector2(70, -4.5), Vector2(91, 0),
		Vector2(70, 4.5), Vector2(22, 5.5),
	])
	draw_colored_polygon(metal, STEEL)
	draw_line(Vector2(25, -2.3), Vector2(86, -0.3), EDGE, 2.3, true)
	draw_line(Vector2(25, 2.4), Vector2(75, 3.0), SHADOW.lightened(0.23), 1.6, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

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
