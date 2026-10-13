extends Node2D
## Bellhollow's bridge is burning while the city falls. Visual atmosphere
## joins the APPROVED painted skyline to the walkable stone surface.
## No dialogue, collision, gameplay state, camera movement or RNG per frame.
##
## Smoke and cinders are deterministic per room; footprints only appear
## when the actual player walks, and fade out without leaving scene nodes.
## Rendering is capped at 15 Hz to protect the Android debug build.

@export var bounds: Rect2 = Rect2(-1280, -360, 2560, 720)
@export_range(0, 25, 1) var smoke_count: int = 12
@export_range(0, 70, 1) var ash_count: int = 36
@export_range(36.0, 150.0, 1.0) var step_distance: float = 76.0

const DRAW_INTERVAL := 1.0 / 15.0
const FOOT_LIFETIME := 0.72
const MAX_FOOTPRINTS := 10
const FOOT_BASELINE := Vector2(0.0, 58.0)
const SMOKE := Color(0.16, 0.158, 0.168)
const HEAT := Color(0.49, 0.24, 0.165)
const CINDER := Color(1.0, 0.57, 0.31)
const ASH := Color(0.63, 0.57, 0.55)

var _time := 0.0
var _draw_accum := 0.0
var _smoke: Array[Dictionary] = []
var _ash: Array[Dictionary] = []
var _footprints: Array[Dictionary] = []
var _player: Node2D = null
var _has_last_position := false
var _last_player_pos := Vector2.ZERO
var _step_travel := 0.0

func _ready() -> void:
	# Both this node and WalkableBridge draw at -1; scene order places
	# faint smoke on TOP of the deck but BEHIND Mollosar and all NPCs.
	z_as_relative = false
	z_index = -1
	_player = get_parent().get_node_or_null("Player") as Node2D
	_generate()
	queue_redraw()


func _generate() -> void:
	_smoke.clear()
	_ash.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = 11378
	for i in range(smoke_count):
		_smoke.append({
			"origin": Vector2(
				rng.randf_range(bounds.position.x + 90.0, bounds.end.x - 90.0),
				rng.randf_range(-144.0, -69.0)),
			"phase": rng.randf_range(0.0, TAU),
			"speed": rng.randf_range(0.23, 0.48),
			"width": rng.randf_range(37.0, 72.0),
			"depth": rng.randf_range(0.35, 1.0)
		})
	for i in range(ash_count):
		_ash.append({
			"origin": Vector2(
				rng.randf_range(bounds.position.x + 10.0, bounds.end.x - 10.0),
				rng.randf_range(-92.0, 274.0)),
			"phase": rng.randf_range(0.0, TAU),
			"speed": rng.randf_range(0.38, 0.91),
			"warm": rng.randf() < 0.24,
			"radius": rng.randf_range(0.75, 1.8)
		})


## Mathematical paths, suitable for deterministic Godot regression tests.
## No teleport at loop boundaries and no large displacement through walls.
static func smoke_offset(elapsed: float, phase: float, speed: float) -> Vector2:
	var t := maxf(elapsed, 0.0)
	return Vector2(sin(phase + t * speed) * 27.0,
		sin(phase * 1.7 + t * speed * 0.61) * 12.0)


static func ash_offset(elapsed: float, phase: float, speed: float) -> Vector2:
	var t := maxf(elapsed, 0.0)
	return Vector2(sin(phase + t * speed * 0.74) * 18.0,
		sin(phase * 1.33 + t * speed) * 18.0)


static func footprint_opacity(age: float) -> float:
	return clampf(1.0 - maxf(age, 0.0) / FOOT_LIFETIME, 0.0, 1.0)


func _process(delta: float) -> void:
	if delta <= 0.0:
		return
	_time += delta
	_draw_accum += delta
	_track_player_steps()
	for i in range(_footprints.size() - 1, -1, -1):
		var f: Dictionary = _footprints[i]
		f["age"] = float(f["age"]) + delta
		if float(f["age"]) >= FOOT_LIFETIME:
			_footprints.remove_at(i)
		else:
			_footprints[i] = f
	if _draw_accum < DRAW_INTERVAL:
		return
	_draw_accum = fposmod(_draw_accum, DRAW_INTERVAL)
	queue_redraw()


func _track_player_steps() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var pos := _player.global_position
	if not _has_last_position:
		_last_player_pos = pos
		_has_last_position = true
		return
	var moved := pos.distance_to(_last_player_pos)
	_last_player_pos = pos
	# Teleports/cutscenes cannot leave a streak of footprints or grant
	# accumulated step credit. Only ordinary on-foot movement emits.
	if moved < 0.3 or moved > 70.0:
		if moved > 70.0:
			_step_travel = 0.0
		return
	_step_travel += moved
	if _step_travel >= step_distance:
		_step_travel = fposmod(_step_travel, step_distance)
		_add_footprint(pos + FOOT_BASELINE)


func _add_footprint(world_pos: Vector2) -> void:
	# Keep the gameplay corridor clean: just two small ash wisps beside
	# the painted feet, never a large opaque debug-colored circle.
	_footprints.append({"position": to_local(world_pos), "age": 0.0,
		"side": -1.0 if _footprints.size() % 2 == 0 else 1.0})
	if _footprints.size() > MAX_FOOTPRINTS:
		_footprints.pop_front()


func _draw() -> void:
	for puff in _smoke:
		_draw_smoke(puff)
	for particle in _ash:
		_draw_ash(particle)
	for f in _footprints:
		_draw_footprint(f)


func _draw_smoke(puff: Dictionary) -> void:
	var phase := float(puff["phase"])
	var speed := float(puff["speed"])
	var center: Vector2 = puff["origin"] + smoke_offset(_time, phase, speed)
	var width := float(puff["width"])
	var depth := float(puff["depth"])
	var breath := 0.82 + 0.18 * sin(_time * speed * 0.8 + phase)
	# Three overlapping layers read as distant billowing smoke rather
	# than an opaque flat disc or repeated geometric foreground prop.
	for j in range(3):
		var spread := Vector2(float(j - 1) * width * 0.44,
			-sin(phase + float(j)) * width * 0.18)
		var shade := SMOKE if j != 1 else HEAT
		shade.a = (0.065 if j != 1 else 0.026) * depth * breath
		draw_circle(center + spread, width * (0.72 + float(j) * 0.06), shade)


func _draw_ash(mote: Dictionary) -> void:
	var phase := float(mote["phase"])
	var speed := float(mote["speed"])
	var p: Vector2 = mote["origin"] + ash_offset(_time, phase, speed)
	var warm := bool(mote["warm"])
	var color := CINDER if warm else ASH
	var twinkle := 0.58 + 0.42 * sin(phase + _time * speed * 2.1)
	color.a = (0.58 if warm else 0.22) * twinkle
	if warm:
		var halo := HEAT
		halo.a = color.a * 0.15
		draw_circle(p, float(mote["radius"]) * 3.3, halo)
	draw_circle(p, float(mote["radius"]), color)


func _draw_footprint(f: Dictionary) -> void:
	var fade := footprint_opacity(float(f["age"]))
	if fade <= 0.0:
		return
	var p: Vector2 = f["position"]
	var side := float(f["side"])
	var step := 1.0 - fade
	var smoke := ASH
	smoke.a = 0.19 * fade
	var highlight := HEAT
	highlight.a = 0.055 * fade
	draw_circle(p + Vector2(12.0 * side + step * 10.0, -step * 12.0),
		5.0 + step * 8.0, smoke)
	draw_circle(p + Vector2(-9.0 * side - step * 6.0, -4.0 - step * 8.0),
		4.0 + step * 5.0, highlight)


func get_smoke_count() -> int:
	return _smoke.size()


func get_ash_count() -> int:
	return _ash.size()


func get_footprint_count() -> int:
	return _footprints.size()
