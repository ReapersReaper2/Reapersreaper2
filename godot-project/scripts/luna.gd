extends Node2D
## Luna follower stub: a small purple light-orb with butterfly-like wings.
## CANON: Luna is a SEPARATE follower entity — never baked into Mollosar's sprite.
## Trail behavior: breadcrumb history of the target's position, following
## ~trail_delay seconds behind. Later systems (affinity, guide-touch
## targeting) will build on this stub.

@export var trail_delay: float = 1.2       ## seconds behind the target
@export var follow_speed: float = 260.0    ## px/s chase speed
@export var stop_distance: float = 60.0    ## hover ring: never overlaps target
@export var teleport_distance: float = 600.0 ## snap on room transitions
@export var sample_interval: float = 0.05  ## position-history sampling
@export var bob_amplitude: float = 6.0      ## hover bob, px
@export var bob_frequency: float = 3.0      ## hover bob, rad/s
@export var flap_frequency: float = 16.0    ## wing flap, rad/s

var target: Node2D = null
var active: bool = true

var _history: Array = []  # Array of [float time, Vector2 pos]
var _sample_accum: float = 0.0
var _time: float = 0.0

var _visual: Node2D = null
var _wing_l: Polygon2D = null
var _wing_r: Polygon2D = null


func set_target(t: Node2D) -> void:
	"""Bind the follow target (usually the player)."""
	target = t
	_history.clear()
	if target != null:
		_history.append([_time, target.global_position])


func get_target() -> Node2D:
	return target


func set_active(v: bool) -> void:
	"""Show/hide Luna (cutscenes where she is absent)."""
	active = v
	visible = v
	set_physics_process(v)


func _physics_process(delta: float) -> void:
	_time += delta
	_cache_visuals()
	_animate(_time)
	if not active or target == null:
		return
	_sample_history(delta)
	_follow(delta)


func _cache_visuals() -> void:
	if _visual == null:
		_visual = get_node_or_null("Visual") as Node2D
	if _wing_l == null and _visual != null:
		_wing_l = _visual.get_node_or_null("WingL") as Polygon2D
	if _wing_r == null and _visual != null:
		_wing_r = _visual.get_node_or_null("WingR") as Polygon2D


func _animate(t: float) -> void:
	if _visual == null:
		return
	_visual.position.y = sin(t * bob_frequency) * bob_amplitude
	if _wing_l != null:
		_wing_l.scale.y = 1.0 + sin(t * flap_frequency) * 0.35
	if _wing_r != null:
		_wing_r.scale.y = 1.0 + sin(t * flap_frequency + PI * 0.15) * 0.35


func _sample_history(delta: float) -> void:
	_sample_accum += delta
	if _sample_accum < sample_interval:
		return
	_sample_accum = 0.0
	_history.append([_time, target.global_position])
	# Prune anything older than the trail window (plus margin).
	var cutoff: float = _time - trail_delay - 0.5
	while _history.size() > 1 and _history[0][0] < cutoff:
		_history.pop_front()


func _trail_point() -> Vector2:
	if _history.is_empty():
		return target.global_position
	var want: float = _time - trail_delay
	# Oldest sample at or before the trail time; fall back to oldest.
	var point: Vector2 = _history[0][1]
	for entry in _history:
		if entry[0] <= want:
			point = entry[1]
		else:
			break
	return point


func _follow(delta: float) -> void:
	var to_player: Vector2 = target.global_position - global_position
	if to_player.length() > teleport_distance:
		# Room transition or spawn: snap beside the player, reseed history.
		global_position = target.global_position + Vector2(-40, 20)
		_history.clear()
		_history.append([_time, target.global_position])
		return
	var goal: Vector2 = _trail_point()
	var to_goal: Vector2 = goal - global_position
	if to_goal.length() > stop_distance:
		var step: Vector2 = to_goal.normalized() * follow_speed * delta
		# Don't overshoot past the stop ring.
		var max_step: float = to_goal.length() - stop_distance
		if step.length() > max_step:
			step = to_goal.normalized() * max_step
		global_position += step
