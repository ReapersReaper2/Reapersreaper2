extends CharacterBody2D
## Greybox training dummy: HP, white hit-flash, knockback, death poof.
## Lives in the "hittable" group; the scythe hitbox calls take_hit().

signal died(dummy)

const CombatTime = preload("res://scripts/combat_time.gd")

@export var max_hp: int = 3
@export var knockback_speed: float = 420.0
@export var knockback_friction: float = 1100.0

var hp: int = 3

var _flash: float = 0.0
var _base_color := Color(0.85, 0.68, 0.38)
var _body: ColorRect = null
var _hp_label: Label = null


func _ready() -> void:
	hp = max_hp
	_body = $Body as ColorRect
	_hp_label = $HPLabel as Label
	_refresh_visuals()


func take_hit(damage: int, from_dir: Vector2) -> void:
	if hp <= 0:
		return
	hp = maxi(0, hp - damage)
	_flash = 1.0
	velocity = from_dir * knockback_speed
	_refresh_visuals()
	if hp <= 0:
		_die()


func _physics_process(delta: float) -> void:
	# Combat-scaled: knockback hangs mid-launch during hitstop, then flies.
	var dt: float = delta * CombatTime.scale
	velocity = velocity.move_toward(Vector2.ZERO, knockback_friction * dt)
	move_and_slide()
	if _flash > 0.0:
		# Unscaled on purpose: the flash reads even through hitstop.
		_flash = maxf(0.0, _flash - delta * 6.0)
		_refresh_visuals()


func _refresh_visuals() -> void:
	if _body != null:
		_body.color = _base_color.lerp(Color(1, 1, 1), _flash)
	if _hp_label != null:
		_hp_label.text = str(hp)


func _die() -> void:
	var poof := Poof.new()
	poof.position = global_position + Vector2(0, -32)
	get_parent().add_child(poof)
	died.emit(self)
	queue_free()


## Placeholder death burst: expanding ring + six embers, no particles needed.
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
			Color(1, 1, 1, 0.8 * (1.0 - p)), 4.0)
		for i in range(6):
			var a: float = TAU * float(i) / 6.0 + p * 2.0
			var r: float = 20.0 + 50.0 * p
			draw_circle(Vector2(cos(a), sin(a)) * r, 5.0 * (1.0 - p) + 1.0,
				Color(1.0, 0.9, 0.6, 0.9 * (1.0 - p)))
