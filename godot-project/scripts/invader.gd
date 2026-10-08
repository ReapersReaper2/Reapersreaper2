extends CharacterBody2D
## Greybox invader for the P1 bridge fight: walks at the player, telegraphs
## a melee swipe, takes scythe hits.
##
## NOTE: intentionally no class_name (project convention).
## Lives in the "hittable" group on physics layer 4 — the exact pattern
## dummy.gd uses, so the scythe hitbox sees it with no changes.

signal died(invader)

const CombatTime = preload("res://scripts/combat_time.gd")

@export var max_hp: int = 3
@export var walk_speed: float = 95.0
@export var damage: int = 1
@export var attack_range: float = 56.0
## Telegraph time before the swipe lands (combat-scaled: hangs in hitstop).
@export var attack_windup: float = 0.45
@export var attack_cooldown: float = 1.4
@export var knockback_speed: float = 420.0
@export var knockback_friction: float = 1100.0
@export var stun_time: float = 0.30
@export var body_color: Color = Color(0.55, 0.16, 0.16)

var hp: int = 3

# Untyped on purpose: dynamic dispatch, no global class cache dependency.
var target = null

var _flash: float = 0.0
var _facing: Vector2 = Vector2.LEFT
var _windup_t: float = -1.0
var _cooldown_t: float = 0.0
var _stun_t: float = 0.0
var _swipe_flash: float = 0.0
var _hp_label: Label = null


func _ready() -> void:
	hp = max_hp
	_hp_label = $HPLabel as Label
	_refresh_hp()


func take_hit(dmg: int, from_dir: Vector2) -> void:
	if hp <= 0:
		return
	hp = maxi(0, hp - dmg)
	_flash = 1.0
	# Getting hit interrupts the swipe and staggers the invader.
	_windup_t = -1.0
	_stun_t = stun_time
	velocity = from_dir * knockback_speed
	_refresh_hp()
	if hp <= 0:
		_die()


func is_alive() -> bool:
	return hp > 0


func _physics_process(delta: float) -> void:
	if hp <= 0:
		return
	# Combat-scaled: knockback and wind-ups hang mid-launch during hitstop.
	var dt: float = delta * CombatTime.scale

	# Knockback decay always applies; stun suppresses the AI.
	velocity = velocity.move_toward(Vector2.ZERO, knockback_friction * dt)
	if _stun_t > 0.0:
		_stun_t -= dt
	else:
		velocity = Vector2.ZERO
		_ai(dt)

	if _cooldown_t > 0.0:
		_cooldown_t -= dt

	move_and_slide()

	# Unscaled on purpose: flashes read even through hitstop.
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta * 6.0)
	if _swipe_flash > 0.0:
		_swipe_flash = maxf(0.0, _swipe_flash - delta * 8.0)
	queue_redraw()


func _ai(dt: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	if target.has_method("is_alive") and not target.is_alive():
		return
	var to: Vector2 = target.global_position - global_position
	var dist: float = to.length()
	if dist > 1.0:
		_facing = to.normalized()

	if _windup_t >= 0.0:
		# Winding up: plant feet, then the swipe lands.
		_windup_t += dt
		if _windup_t >= attack_windup:
			_land_swipe()
		return

	if dist <= attack_range:
		if _cooldown_t <= 0.0:
			_windup_t = 0.0
	else:
		velocity = _facing * walk_speed


func _land_swipe() -> void:
	_windup_t = -1.0
	_cooldown_t = attack_cooldown
	_swipe_flash = 1.0
	if target == null or not is_instance_valid(target):
		return
	var to: Vector2 = target.global_position - global_position
	if to.length() <= attack_range * 1.35 and target.has_method("take_damage"):
		if target.has_method("take_damage_from"):
			target.take_damage_from(damage, self, [])
		else:
			target.take_damage(damage)


func _refresh_hp() -> void:
	if _hp_label != null:
		_hp_label.text = str(hp)


func _die() -> void:
	var poof := Poof.new()
	poof.position = global_position + Vector2(0, -32)
	get_parent().add_child(poof)
	_stats_hook("record_kill")
	died.emit(self)
	queue_free()


## Feed the achievement stat tracker (null-safe: headless tests have no Stats).
func _stats_hook(method: String) -> void:
	if not is_inside_tree():
		return
	var st = get_node_or_null("/root/Stats")
	if st != null and st.has_method(method):
		st.call(method)


func _draw() -> void:
	var center := Vector2(0, -32)
	var col: Color = body_color.lerp(Color(1, 1, 1), _flash)
	# Body: dark red disc.
	draw_circle(center, 20.0, col)
	draw_arc(center, 20.0, 0.0, TAU, 20, col.darkened(0.35), 3.0)
	# Direction tick: small triangle pointing at the facing.
	var tip: Vector2 = center + _facing * 30.0
	var side: Vector2 = _facing.rotated(PI * 0.5) * 8.0
	draw_colored_polygon(PackedVector2Array([
		tip, center + _facing * 12.0 + side, center + _facing * 12.0 - side,
	]), col.lightened(0.25))
	# Wind-up telegraph: arc that fills as the swipe charges.
	if _windup_t >= 0.0:
		var p: float = clampf(_windup_t / attack_windup, 0.0, 1.0)
		var a0: float = _facing.angle() - 0.9
		draw_arc(center, 34.0, a0, a0 + 1.8 * p, 16,
			Color(1.0, 0.25, 0.2, 0.9), 5.0)
	# Swipe flash: quick white arc on landing.
	if _swipe_flash > 0.0:
		var a: float = _facing.angle()
		draw_arc(center, 30.0, a - 0.9, a + 0.9, 16,
			Color(1, 1, 1, 0.85 * _swipe_flash), 6.0)


## Placeholder death burst: expanding ring + six embers (same as dummy's).
class Poof extends Node2D:
	var t: float = 0.0

	func _process(delta: float) -> void:
		t += delta
		if t >= 0.45:
			queue_free()
		else:
			queue_redraw()

	func _draw() -> void:
		var p: float = clampf(t / 0.45, 0.0, 1.0)
		draw_arc(Vector2.ZERO, 12.0 + 60.0 * p, 0.0, TAU, 24,
			Color(1, 0.45, 0.4, 0.8 * (1.0 - p)), 4.0)
		for i in range(6):
			var a: float = TAU * float(i) / 6.0 + p * 2.0
			var r: float = 20.0 + 50.0 * p
			draw_circle(Vector2(cos(a), sin(a)) * r, 5.0 * (1.0 - p) + 1.0,
				Color(1.0, 0.5, 0.45, 0.9 * (1.0 - p)))
