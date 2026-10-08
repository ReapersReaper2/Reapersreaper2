extends CharacterBody2D
## Plant tendril — one of Harrow's three damage-gate tendrils (GD5).
## 30 Vigor each. While any tendril lives, Harrow is invulnerable:
## "break his concentration, then he can be damaged."
##
## NOTE: intentionally no class_name (project convention).
## Lives in the "hittable" group on physics layer 4 — the exact pattern
## dummy.gd uses, so the scythe hitbox sees it with no changes.

signal died(tendril)

## Locked stat block (decision log): 30 Vigor each.
@export var max_vigor: int = 30
@export var swipe_damage: int = 1

enum TState { IDLE, WINDUP, STRIKE, STAGGER, DEAD }

var vigor: int = 30
var state: int = TState.IDLE

var _state_t: float = 0.0
var _cooldown_t: float = 0.0
var _sway_t: float = 0.0
var _flash: float = 0.0
var _strike_done: bool = false

var target = null
var _hp_label: Label = null


func _ready() -> void:
	vigor = max_vigor
	add_to_group("hittable")
	collision_layer = 16
	collision_mask = 1
	_sway_t = randf() * TAU
	_hp_label = Label.new()
	_hp_label.name = "HPLabel"
	_hp_label.position = Vector2(-20, -96)
	_hp_label.add_theme_font_size_override("font_size", 15)
	add_child(_hp_label)
	_refresh_hp()


func _physics_process(delta: float) -> void:
	if state == TState.DEAD:
		return
	_state_t += delta
	_sway_t += delta * 1.7
	_flash = maxf(0.0, _flash - delta * 4.0)
	_cooldown_t = maxf(0.0, _cooldown_t - delta)
	_resolve_target()
	# Tendrils are rooted: they sway, they don't walk.
	velocity = Vector2.ZERO
	if target != null and is_instance_valid(target) and state == TState.IDLE:
		var d: float = (target.global_position - global_position).length()
		if d < 110.0 and _cooldown_t <= 0.0:
			_enter(TState.WINDUP)
	match state:
		TState.WINDUP:
			if _state_t >= 0.6:
				_enter(TState.STRIKE)
		TState.STRIKE:
			if not _strike_done:
				_strike_done = true
				_apply_swipe()
			if _state_t >= 0.35:
				_cooldown_t = 1.8
				_enter(TState.IDLE)
		TState.STAGGER:
			if _state_t >= 0.25:
				_enter(TState.IDLE)
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


func _apply_swipe() -> void:
	if target == null or not is_instance_valid(target):
		return
	if not target.has_method("take_damage_from"):
		return
	if (target.global_position - global_position).length() <= 120.0:
		target.take_damage_from(swipe_damage, self, ["plant"])


func take_hit(dmg: int, from_dir: Vector2) -> void:
	if state == TState.DEAD:
		return
	vigor = maxi(0, vigor - dmg)
	_flash = 1.0
	_enter(TState.STAGGER)
	_refresh_hp()
	if vigor <= 0:
		_die()


func is_alive() -> bool:
	return state != TState.DEAD


func _die() -> void:
	_enter(TState.DEAD)
	died.emit(self)


func _refresh_hp() -> void:
	if _hp_label != null:
		_hp_label.text = "%d" % vigor


func _draw() -> void:
	# Greybox: pale tendril-pillar, swaying.
	var sway := sin(_sway_t) * 10.0
	var col := Color(0.75, 0.82, 0.78)
	if _flash > 0.0:
		col = Color.WHITE.lerp(col, 1.0 - _flash)
	var windup := state == TState.WINDUP
	var pts := PackedVector2Array()
	for i in 7:
		var f := float(i) / 6.0
		pts.append(Vector2(lerpf(0.0, sway, f), lerpf(30.0, -80.0, f)))
	draw_polyline(pts, col.lerp(Color(1.0, 0.6, 0.2), 0.5 if windup else 0.0), 14.0 - 8.0 * 0.0)
	# Root flare.
	draw_colored_polygon(
		PackedVector2Array([Vector2(-22, 30), Vector2(22, 30), Vector2(10, 0), Vector2(-10, 0)]),
		col.darkened(0.35)
	)
	# Telegraph arc on windup.
	if windup:
		draw_arc(Vector2.ZERO, 120.0, 0.0, TAU, 28, Color(0.6, 1.0, 0.6, 0.5), 2.0)
