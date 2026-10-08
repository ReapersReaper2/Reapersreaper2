extends Node2D
## Scythe swing controller (child "ScytheRig" of the player).
##
## Committed two-hit combo: SWING1 (~0.35s) chains into SWING2 (~0.30s,
## reversed arc) if swing is pressed again during SWING1's late window, then
## a short RECOVER cooldown. The player is movement-locked for the whole
## sequence — swings commit, they don't cancel into movement.
##
## Feel hooks: hitstop via CombatTime (combat-scoped, UI-safe), trauma shake
## on the player camera, and a toggleable debug arc so the active frames read
## clearly. Hit detection is group-based ("hittable") with a per-swing hit
## set, so each body is struck once per swing.
##
## DATA-DRIVEN: tuning numbers (timings, hitstop, trauma, arc, damage) come
## from WeaponData's weapon x power-source table, read at swing start from
## GameState's current weapon/power. The @export vars below remain as the
## scythe/armor baseline and as fallbacks if no GameState is present.

signal swing_started(index: int)
signal swing_ended
## Emitted when a swing finishes without hitting anything — feeds
## Despair Feed (Harrow) and any future whiff-reactive systems.
signal swing_whiffed

enum State { IDLE, SWING1, SWING2, RECOVER }

const CombatTime = preload("res://scripts/combat_time.gd")
const WeaponData = preload("res://scripts/weapon_data.gd")
const Depower = preload("res://scripts/depower.gd")
const SporeNeedle = preload("res://scripts/spore_needle.gd")

@export var swing1_time: float = 0.35
@export var swing2_time: float = 0.30
@export var recover_time: float = 0.28
## Damaging window, as fractions of the swing duration.
@export var active_from: float = 0.20
@export var active_to: float = 0.70
## Pressing swing again after this fraction of SWING1 queues the combo.
@export var combo_from: float = 0.55
@export var hitstop_duration: float = 0.07
@export var shake_trauma: float = 0.32
@export var show_debug_arc: bool = true
@export var arc_radius: float = 150.0
@export var arc_half_angle_deg: float = 75.0

var state: int = State.IDLE

var _swing_t: float = 0.0
var _combo_queued: bool = false
var _was_active: bool = false
var _hit_this_swing: Array = []
## True when swing 1 of the current combo landed at least one hit —
## used for the full_combo achievement when swing 2 connects.
var _swing1_landed: bool = false
var _combo_reported: bool = false
## Tuning snapshot for the current swing, from WeaponData (scythe.gd reads
## it once per swing so a mid-combat weapon/power change can't desync a
## swing's timings). Falls back to the @export baselines if GameState is
## absent (headless tests without autoloads).
var _entry: Dictionary = {}

# Untyped on purpose: cross-script calls (move_locked, facing, take_hit)
# use dynamic dispatch so nothing depends on the global class cache.
var _player = null
var _hitbox: Area2D = null


func _ready() -> void:
	_player = get_parent()
	_hitbox = $Hitbox as Area2D
	if not _hitbox.body_entered.is_connected(_on_hitbox_body_entered):
		_hitbox.body_entered.connect(_on_hitbox_body_entered)


func try_swing() -> void:
	match state:
		State.IDLE:
			_start_swing(1)
		State.SWING1:
			if _swing_t >= swing1_time * combo_from:
				_combo_queued = true
		# SWING2 and RECOVER: committed — no buffering, no cancel.


func is_swinging() -> bool:
	return state != State.IDLE


func _start_swing(index: int) -> void:
	state = State.SWING1 if index == 1 else State.SWING2
	_swing_t = 0.0
	_combo_queued = false
	_was_active = false
	# Capture swing-1's hits before clearing: a swing-2 hit after a
	# swing-1 hit is a full combo (feeds the achievement tracker).
	_swing1_landed = (index == 2) and not _hit_this_swing.is_empty()
	_combo_reported = false
	_hit_this_swing.clear()
	_entry = _resolve_entry()
	_player.move_locked = true
	_player.velocity = _player.velocity.move_toward(Vector2.ZERO, 1200.0)
	rotation = _snap8(_player.facing).angle()
	swing_started.emit(index)
	queue_redraw()


## Read the (weapon, power) tuning entry for this swing. Without a live
## GameState (headless tests), use the scythe/armor baseline.
func _resolve_entry() -> Dictionary:
	var gs = null
	if _player != null:
		gs = _player.get_node_or_null("/root/GameState")
	if gs == null:
		return WeaponData.get_entry("scythe", "armor")
	return WeaponData.get_entry(WeaponData.current_weapon(gs), WeaponData.current_power(gs))


func _physics_process(delta: float) -> void:
	if state == State.IDLE:
		return
	# Combat-scaled delta: the swing hangs on its impact frame during hitstop.
	var dt: float = delta * CombatTime.scale
	_swing_t += dt
	var active: bool = _in_active_window()
	if active and not _was_active:
		_sweep_overlaps()
	_was_active = active
	if _swing_t >= _swing_duration():
		_advance()
	queue_redraw()


func _swing_duration() -> float:
	match state:
		State.SWING1:
			return float(_entry.get("swing1_time", swing1_time))
		State.SWING2:
			return float(_entry.get("swing2_time", swing2_time))
		State.RECOVER:
			return recover_time
	return 0.0


func _in_active_window() -> bool:
	if state != State.SWING1 and state != State.SWING2:
		return false
	var f: float = _swing_t / _swing_duration()
	return f >= active_from and f <= active_to


func _advance() -> void:
	if state == State.SWING1 and _combo_queued:
		_start_swing(2)
	elif state == State.SWING1 or state == State.SWING2:
		# Whiff check before the swing state changes: Despair Feed.
		var whiffed := _hit_this_swing.is_empty()
		state = State.RECOVER
		_swing_t = 0.0
		_was_active = false
		if whiffed:
			swing_whiffed.emit()
	elif state == State.RECOVER:
		state = State.IDLE
		_swing_t = 0.0
		_player.move_locked = false
		swing_ended.emit()
	queue_redraw()


## Catch bodies already overlapping when the active window opens (they never
## emit body_entered, so a pure signal approach would whiff point-blank).
func _sweep_overlaps() -> void:
	for body in _hitbox.get_overlapping_bodies():
		_try_hit(body)


func _on_hitbox_body_entered(body: Node2D) -> void:
	_try_hit(body)


func _try_hit(body: Node2D) -> void:
	if state != State.SWING1 and state != State.SWING2:
		return
	if not _in_active_window():
		return
	var target = body
	if target in _hit_this_swing:
		return
	if not target.is_in_group("hittable"):
		return
	if not target.has_method("take_hit"):
		return
	_hit_this_swing.append(target)
	var to: Vector2 = target.global_position - _player.global_position
	var dir: Vector2 = to.normalized() if to.length() > 1.0 else Vector2.RIGHT.rotated(rotation)
	CombatTime.hitstop(float(_entry.get("hitstop_duration", hitstop_duration)))
	var cam = _player.get_node_or_null("Camera2D")
	if cam != null and cam.has_method("add_trauma"):
		cam.add_trauma(float(_entry.get("shake_trauma", shake_trauma)))
	var dmg: int = maxi(1, int(round(float(_entry.get("damage_mult", 1.0)))))
	# Ch13-14 depower: scythe hits at 50% (full) or 75% (partial).
	dmg = maxi(1, int(round(float(dmg) * Depower.damage_mult(_dep_game_state()))))
	target.take_hit(dmg, dir)
	# Spore Needle (Forms 5/6): the hit is a spore-tipped needle strike —
	# infect the creature it struck. fire_needle() no-ops for non-creature
	# targets and wrong forms, and is null-safe without a GameState.
	SporeNeedle.fire_needle(_dep_game_state(), target)
	# Full combo: swing 2 landed after swing 1 landed (report once).
	if state == State.SWING2 and _swing1_landed and not _combo_reported:
		_combo_reported = true
		_stats_record_combo(2)


## Feed the achievement stat tracker (null-safe: headless tests have no Stats).
func _stats_record_combo(hits: int) -> void:
	var p = _player
	if p == null or not is_instance_valid(p):
		return
	if not p.is_inside_tree():
		return
	var st = p.get_node_or_null("/root/Stats")
	if st != null and st.has_method("record_combo_hits"):
		st.record_combo_hits(hits)


## GameState lookup for depower queries (null-safe in headless tests).
func _dep_game_state():
	if _player != null and is_instance_valid(_player) and _player.has_method("_game_state"):
		return _player._game_state()
	return null


func _snap8(v: Vector2) -> Vector2:
	if v.length() < 0.01:
		return Vector2.DOWN
	var snapped: float = roundf(v.angle() / (PI / 4.0)) * (PI / 4.0)
	return Vector2(cos(snapped), sin(snapped))


func _draw() -> void:
	if not show_debug_arc:
		return
	if state != State.SWING1 and state != State.SWING2:
		return
	var radius: float = float(_entry.get("arc_radius", arc_radius))
	var base: Color = _entry.get("arc_color", Color(0.70, 0.30, 1.0))
	var half: float = deg_to_rad(arc_half_angle_deg)
	var pts := PackedVector2Array()
	pts.append(Vector2.ZERO)
	var steps := 28
	for i in range(steps + 1):
		var a: float = lerpf(-half, half, float(i) / float(steps))
		pts.append(Vector2(cos(a), sin(a)) * radius)
	draw_colored_polygon(pts, Color(base.r, base.g, base.b, 0.14))
	draw_arc(Vector2.ZERO, radius, -half, half, steps, Color(base.r, base.g, base.b, 0.30), 2.0)
	var prog: float = clampf(_swing_t / _swing_duration(), 0.0, 1.0)
	var edge_a: float
	if state == State.SWING1:
		edge_a = lerpf(-half, half, prog)
	else:
		edge_a = lerpf(half, -half, prog)
	var edge: Vector2 = Vector2(cos(edge_a), sin(edge_a)) * radius
	var edge_col := Color(minf(base.r + 0.10, 1.0), minf(base.g + 0.15, 1.0), base.b, 0.85)
	draw_line(Vector2.ZERO, edge, edge_col, 6.0)
	draw_circle(edge, 8.0, edge_col)
