extends Node2D
## Guide-touch controller (child "GuideRig" of the player).
##
## The tender counterpart to the reap-swing: extend, hold/cradle, release.
## Press E (interact) near a guidable soul to take it up; stay close while
## the soothe meter fills; on full, the soul is guided and released.
## Walking away or taking damage breaks the hold.
##
## ZERO damage — this never calls take_hit() and never reduces HP. The
## scythe and the guide are mutually exclusive: starting a guide locks
## movement and the player script blocks swings while guide_active.
##
## NOTE: intentionally no class_name (project convention).

signal guide_started(wisp)
signal guide_completed(wisp)
signal guide_cancelled

enum State { IDLE, EXTENDING, HOLDING, RELEASING }

@export var guide_range: float = 160.0
@export var extend_time: float = 0.5
@export var soothe_time: float = 2.5
@export var break_distance: float = 230.0
@export var beam_color := Color(0.78, 0.72, 1.0, 0.55)
@export var beam_width: float = 7.0

var state: int = State.IDLE
## 0..1 soothe progress; readable for tests and future UI.
var meter: float = 0.0

# Untyped on purpose: cross-script calls (move_locked, guide_active,
# vigor) use dynamic dispatch so nothing depends on the global class cache.
var _player = null
var _target = null
var _t: float = 0.0
var _vigor_snapshot: int = 0
var _beam: Line2D = null
var _beam_glow: Line2D = null


func _ready() -> void:
	_player = get_parent()
	_beam = $Beam as Line2D
	_beam_glow = $BeamGlow as Line2D
	_apply_beam_style()
	_hide_beam()


func _apply_beam_style() -> void:
	if _beam != null:
		_beam.width = beam_width
		_beam.default_color = beam_color
	if _beam_glow != null:
		_beam_glow.width = beam_width * 2.4
		var c := beam_color
		c.a *= 0.32
		_beam_glow.default_color = c


## E pressed: take up the nearest calm guidable soul in range.
## Returns true when a guide starts (caller should swallow the input).
func try_guide() -> bool:
	if state != State.IDLE:
		return false
	if _player == null:
		return false
	# Can't take up a soul mid-swing — the modes are mutually exclusive.
	var srig = _player.get_node_or_null("ScytheRig")
	if srig != null and srig.has_method("is_swinging") and bool(srig.is_swinging()):
		return false
	var wisp = _nearest_guidable()
	if wisp == null:
		return false
	_target = wisp
	state = State.EXTENDING
	_t = 0.0
	meter = 0.0
	_player.move_locked = true
	_player.guide_active = true
	guide_started.emit(wisp)
	return true


func is_guiding() -> bool:
	return state != State.IDLE


func _nearest_guidable():
	var best = null
	var best_d: float = guide_range
	var origin: Vector2 = _player.global_position
	for node in get_tree().get_nodes_in_group("guidable"):
		if not (node is Node2D):
			continue
		if not node.has_method("is_guidable") or not bool(node.is_guidable()):
			continue
		var d: float = origin.distance_to((node as Node2D).global_position)
		if d < best_d:
			best_d = d
			best = node
	return best


func _physics_process(delta: float) -> void:
	if state == State.IDLE:
		return
	if not is_instance_valid(_target):
		_cancel()
		return
	if state == State.EXTENDING:
		_t += delta
		_update_beam(clampf(_t / extend_time, 0.0, 1.0))
		if _t >= extend_time:
			state = State.HOLDING
			_t = 0.0
			meter = 0.0
			var v = _player.get("vigor")
			_vigor_snapshot = int(v) if v != null else 0
	elif state == State.HOLDING:
		var d: float = _player.global_position.distance_to(_target.global_position)
		if d > break_distance:
			_cancel()
			return
		var v2 = _player.get("vigor")
		if v2 != null and int(v2) < _vigor_snapshot:
			# Hurt mid-hold: the touch breaks.
			_cancel()
			return
		meter = minf(1.0, meter + delta / soothe_time)
		if _target.has_method("soothe"):
			_target.soothe(meter, _player.global_position)
		_update_beam(1.0)
		if meter >= 1.0:
			_begin_release()
	elif state == State.RELEASING:
		# The wisp's release tween plays; its guided signal finishes us.
		_update_beam(maxf(0.0, 1.0 - _t))
		_t += delta


func _begin_release() -> void:
	state = State.RELEASING
	_t = 0.0
	if _target.has_signal("guided"):
		_target.guided.connect(_on_target_guided, CONNECT_ONE_SHOT)
	if _target.has_method("release"):
		_target.release()
	else:
		_finish(_target)


func _on_target_guided(wisp) -> void:
	_finish(wisp)


func _finish(wisp) -> void:
	_hide_beam()
	_unlock_player()
	state = State.IDLE
	meter = 0.0
	_target = null
	guide_completed.emit(wisp)


func _cancel() -> void:
	if _target != null and is_instance_valid(_target) and _target.has_method("cancel_soothe"):
		_target.cancel_soothe()
	_hide_beam()
	_unlock_player()
	state = State.IDLE
	meter = 0.0
	_target = null
	guide_cancelled.emit()


func _unlock_player() -> void:
	if _player != null and is_instance_valid(_player):
		_player.move_locked = false
		_player.guide_active = false


func _update_beam(progress: float) -> void:
	if _target == null or not is_instance_valid(_target):
		_hide_beam()
		return
	var local: Vector2 = to_local(_target.global_position)
	var tip: Vector2 = local * clampf(progress, 0.0, 1.0)
	# Gentle breathing pulse — the opposite of the scythe's snap.
	var pulse: float = 1.0 + 0.14 * sin(Time.get_ticks_msec() / 1000.0 * 3.2)
	for line in [_beam, _beam_glow]:
		if line == null:
			continue
		line.visible = true
		line.points = PackedVector2Array([Vector2(0, -40), tip])
		line.width = (beam_width if line == _beam else beam_width * 2.4) * pulse


func _hide_beam() -> void:
	if _beam != null:
		_beam.visible = false
	if _beam_glow != null:
		_beam_glow.visible = false
