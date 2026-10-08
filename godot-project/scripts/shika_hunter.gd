extends CharacterBody2D
## Shika hunter — one of the two GD4 boss hunters (the Ascent).
## Graceful, predatory, ritualistic. Uses the old Ch3 flame patterns
## (rings / tongues / blackout) sped up, plus a ritual strike.
##
## NOTE: intentionally no class_name (project convention).
## Lives in the "hittable" group on physics layer 4 — the exact pattern
## dummy.gd uses, so the scythe hitbox sees it with no changes.
##
## The shika_boss.gd controller drives the alternating rhythm: only the
## ACTIVE hunter attacks; the other circles. Enrage (partner dead) is a
## speed multiplier the controller sets.

signal died(hunter)

## Locked stat block (decision log, doc 00 Ch13): 80 Vigor / 18 Power /
## 12 Guard / 16 Speed per hunter.
@export var max_vigor: int = 80
@export var power: int = 18
@export var walk_speed: float = 150.0
## Attack cadence; the controller multiplies this when enraged.
@export var attack_speed: float = 1.0

enum HState { IDLE, CIRCLING, WINDUP, STRIKE, RECOVER, STAGGER, DEAD }

var vigor: int = 80
var active: bool = false  # set by the controller; only active attacks
var state: int = HState.IDLE

# Current attack being telegraphed / executed.
var _attack: String = ""
var _state_t: float = 0.0
var _cooldown_t: float = 0.0
var _stun_t: float = 0.0
var _strike_done: bool = false
var _strike_origin: Vector2 = Vector2.ZERO
var _telegraph_r: float = 0.0
var _flash: float = 0.0
var _facing: Vector2 = Vector2.LEFT
var _circle_dir: float = 1.0
var _orbit_center: Vector2 = Vector2.ZERO

var target = null  # the player; dynamic dispatch, no class cache
var _hp_label: Label = null


func _ready() -> void:
	vigor = max_vigor
	add_to_group("hittable")
	collision_layer = 16  # layer 4, like invader/dummy
	collision_mask = 1
	_circle_dir = 1.0 if randf() > 0.5 else -1.0
	_hp_label = Label.new()
	_hp_label.name = "HPLabel"
	_hp_label.position = Vector2(-24, -78)
	_hp_label.add_theme_font_size_override("font_size", 16)
	add_child(_hp_label)
	_refresh_hp()


func _physics_process(delta: float) -> void:
	if state == HState.DEAD:
		return
	_state_t += delta
	_flash = maxf(0.0, _flash - delta * 4.0)
	if _stun_t > 0.0:
		_stun_t -= delta
		velocity = velocity.move_toward(Vector2.ZERO, 1400.0 * delta)
		move_and_slide()
		return
	_cooldown_t = maxf(0.0, _cooldown_t - delta)
	_resolve_target()
	match state:
		HState.IDLE:
			velocity = velocity.move_toward(Vector2.ZERO, 900.0 * delta)
		HState.CIRCLING:
			_circle(delta)
		HState.WINDUP:
			_windup(delta)
		HState.STRIKE:
			_strike(delta)
		HState.RECOVER:
			velocity = velocity.move_toward(Vector2.ZERO, 900.0 * delta)
			if _state_t >= 0.55 / attack_speed:
				_enter(HState.CIRCLING if not active else HState.IDLE)
	move_and_slide()
	queue_redraw()


func _enter(s: int) -> void:
	state = s
	_state_t = 0.0
	_strike_done = false


func _resolve_target() -> void:
	if target != null and is_instance_valid(target):
		return
	if not is_inside_tree():
		return
	target = get_tree().get_first_node_in_group("player")


## The controller calls this when this hunter becomes the active one.
func begin_attack_cycle() -> void:
	if state == HState.DEAD or not active:
		return
	if _cooldown_t > 0.0:
		return
	# Pick a pattern: rings / tongues / blackout / ritual strike.
	var roll := randf()
	if roll < 0.28:
		_attack = "ring"
	elif roll < 0.55:
		_attack = "tongues"
	elif roll < 0.78:
		_attack = "blackout"
	else:
		_attack = "ritual"
	_strike_origin = global_position
	_enter(HState.WINDUP)


func _windup(delta: float) -> void:
	velocity = velocity.move_toward(Vector2.ZERO, 1200.0 * delta)
	if target != null and is_instance_valid(target):
		_facing = (target.global_position - global_position).normalized()
	# Faster than the Ch3 originals — the whole point of the fight.
	var windup_time := 0.55 / attack_speed
	# Telegraph grows so the player can read it.
	_telegraph_r = lerpf(0.0, _attack_radius(), clampf(_state_t / windup_time, 0.0, 1.0))
	if _state_t >= windup_time:
		_enter(HState.STRIKE)


func _attack_radius() -> float:
	match _attack:
		"ring":
			return 130.0
		"tongues":
			return 170.0
		"blackout":
			return 90.0
		"ritual":
			return 110.0
	return 110.0


func _strike(delta: float) -> void:
	if _strike_done:
		return
	_strike_done = true
	_apply_strike()
	_cooldown_t = (1.6 if _attack != "ritual" else 2.2) / attack_speed
	_enter(HState.RECOVER)


func _apply_strike() -> void:
	if target == null or not is_instance_valid(target):
		return
	if not target.has_method("take_damage_from"):
		return
	var dmg := 1
	if _attack == "ritual":
		dmg = 2  # the heavy one — learn the rhythm or fall
	var to_player: Vector2 = target.global_position - global_position
	match _attack:
		"ring":
			# Expanding ring: hits if the player is inside the radius
			# but not hugging the hunter (the safe spot is close).
			if to_player.length() > 46.0 and to_player.length() <= _attack_radius():
				target.take_damage_from(dmg, self, ["fire"])
		"tongues":
			# Three flame tongues toward the player: hits in a cone.
			if to_player.length() <= _attack_radius():
				var ang := absf(_facing.angle_to(to_player.normalized()))
				if ang < 0.5:
					target.take_damage_from(dmg, self, ["fire"])
		"blackout":
			# Strike AT the player's position at windup end — safe if
			# they kept moving.
			if to_player.length() <= _attack_radius():
				target.take_damage_from(dmg, self, ["fire"])
		"ritual":
			if to_player.length() <= _attack_radius():
				target.take_damage_from(dmg, self, ["fire"])


func _circle(delta: float) -> void:
	# Inactive hunters orbit the arena center, staying readable.
	if _orbit_center == Vector2.ZERO:
		_orbit_center = global_position
	var to: Vector2 = global_position - _orbit_center
	var ang := to.angle() + _circle_dir * 1.1 * delta
	var r := 220.0
	var want := _orbit_center + Vector2(cos(ang), sin(ang)) * r
	velocity = (want - global_position) * 4.0
	velocity = velocity.limit_length(walk_speed * 0.7)


func take_hit(dmg: int, from_dir: Vector2) -> void:
	if state == HState.DEAD:
		return
	vigor = maxi(0, vigor - dmg)
	_flash = 1.0
	_stun_t = 0.22
	velocity = from_dir * 380.0
	_refresh_hp()
	if vigor <= 0:
		_die()


func is_alive() -> bool:
	return state != HState.DEAD


func enrage() -> void:
	# Partner down: faster. The rhythm gets mean.
	attack_speed = 1.6


## Stance helper for the controller: circling (inactive) or idle (active).
func set_stance(circling: bool) -> void:
	if state == HState.DEAD:
		return
	_enter(HState.CIRCLING if circling else HState.IDLE)


func _die() -> void:
	_enter(HState.DEAD)
	died.emit(self)


func _refresh_hp() -> void:
	if _hp_label != null:
		_hp_label.text = "%d" % vigor


func _draw() -> void:
	# Greybox body: tall hunter silhouette, flame-red when winding up.
	var body := Color(0.42, 0.22, 0.30)
	if _flash > 0.0:
		body = Color.WHITE.lerp(body, 1.0 - _flash)
	var windup_glow := 0.0
	if state == HState.WINDUP:
		windup_glow = clampf(_state_t / 0.55, 0.0, 1.0)
		body = body.lerp(Color(1.0, 0.45, 0.15), windup_glow * 0.7)
	draw_colored_polygon(
		PackedVector2Array([Vector2(-14, 30), Vector2(14, 30), Vector2(8, -38), Vector2(-8, -38)]),
		body
	)
	# Ritual antlers.
	draw_line(Vector2(-8, -38), Vector2(-22, -58), body.darkened(0.2), 3.0)
	draw_line(Vector2(8, -38), Vector2(22, -58), body.darkened(0.2), 3.0)
	# Telegraph ring while winding up.
	if state == HState.WINDUP and _telegraph_r > 1.0:
		draw_arc(Vector2.ZERO, _telegraph_r, 0.0, TAU, 32, Color(1.0, 0.4, 0.1, 0.65), 3.0)
		if _attack == "ring":
			draw_arc(Vector2.ZERO, 46.0, 0.0, TAU, 24, Color(0.4, 1.0, 0.5, 0.5), 2.0)
		elif _attack == "tongues":
			var base := _facing.angle()
			for off in [-0.5, 0.0, 0.5]:
				var d := Vector2(cos(base + off), sin(base + off))
				draw_line(Vector2.ZERO, d * _attack_radius(), Color(1.0, 0.5, 0.15, 0.4), 10.0)
