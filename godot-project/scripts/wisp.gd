extends Node2D
## Guidable soul for the guide-touch mechanic (C1's first bounty, etc).
##
## NOTE: intentionally no class_name (project convention).
## ZERO-damage entity by construction: it is NOT in the "hittable" group
## and has no take_hit() method, so the scythe hitbox can never affect it.
## States: IDLE (flickering drift) -> SOOTHED (during a guide hold: the
## flicker steadies, the color warms, it drifts toward the guide) ->
## GUIDED (release: it rises, fades, emits guided, then frees itself).

signal guided(wisp)

enum WispState { IDLE, SOOTHED, GUIDED }

@export var drift_radius: float = 36.0
@export var drift_speed: float = 0.55
@export var release_rise: float = 130.0
@export var release_time: float = 1.6
@export var cool_color := Color(0.62, 0.72, 0.95)
@export var warm_color := Color(0.98, 0.94, 0.86)

var wisp_state: int = WispState.IDLE

var _anchor: Vector2 = Vector2.ZERO
var _t: float = 0.0
var _soothe: float = 0.0
var _drift_target: Vector2 = Vector2.ZERO
var _visual: Node2D = null
var _orb: Polygon2D = null
var _release_tween: Tween = null


func _ready() -> void:
	add_to_group("guidable")
	_anchor = position
	_visual = $Visual as Node2D
	_orb = $Visual/Orb as Polygon2D


## Only a calm, idle wisp can be taken up. A wisp already being soothed
## or released refuses a second guide.
func is_guidable() -> bool:
	return wisp_state == WispState.IDLE


## Called every physics frame by the GuideRig during HOLDING.
## progress: 0..1 soothe meter. toward: world position to drift to.
func soothe(progress: float, toward: Vector2) -> void:
	if wisp_state == WispState.GUIDED:
		return
	wisp_state = WispState.SOOTHED
	_soothe = clampf(progress, 0.0, 1.0)
	_drift_target = toward


## The hold broke (walked away / hurt). Settle back into idle drift
## from wherever it ended up — no snap-back.
func cancel_soothe() -> void:
	if wisp_state == WispState.GUIDED:
		return
	wisp_state = WispState.IDLE
	_soothe = 0.0
	_anchor = position


## The meter filled: the soul is guided. Rises gently, fades, emits
## guided, then frees itself.
func release() -> void:
	if wisp_state == WispState.GUIDED:
		return
	wisp_state = WispState.GUIDED
	_soothe = 1.0
	if _release_tween != null and _release_tween.is_valid():
		_release_tween.kill()
	_release_tween = create_tween().set_parallel(true)
	_release_tween.tween_property(self, "position:y", position.y - release_rise, release_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_release_tween.tween_property(_visual, "modulate:a", 0.0, release_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_release_tween.chain().tween_callback(_on_release_done)


func _on_release_done() -> void:
	_stats_hook("record_guide")
	guided.emit(self)
	queue_free()


## Feed the achievement stat tracker (null-safe: headless tests have no Stats).
func _stats_hook(method: String) -> void:
	if not is_inside_tree():
		return
	var st = get_node_or_null("/root/Stats")
	if st != null and st.has_method(method):
		st.call(method)


func _process(delta: float) -> void:
	_t += delta
	if wisp_state == WispState.GUIDED:
		return
	if wisp_state == WispState.SOOTHED:
		# Flicker steadies as the soothe deepens; drift toward the guide.
		var amp: float = lerpf(0.30, 0.04, _soothe)
		var a: float = 0.72 + amp * sin(_t * 7.0)
		_visual.modulate.a = clampf(a, 0.0, 1.0)
		position = position.lerp(_drift_target + Vector2(0, -46), clampf(delta * 1.6, 0.0, 1.0))
		if _orb != null:
			_orb.color = cool_color.lerp(warm_color, _soothe)
	else:
		# Idle: restless flicker, slow wander around the anchor.
		var a2: float = 0.55 + 0.28 * sin(_t * 7.0) + 0.10 * sin(_t * 13.7)
		_visual.modulate.a = clampf(a2, 0.0, 1.0)
		position = _anchor + Vector2(sin(_t * drift_speed), cos(_t * drift_speed * 0.8)) * drift_radius
		if _orb != null:
			_orb.color = cool_color
