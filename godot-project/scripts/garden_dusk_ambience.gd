extends Node2D
## Small, deterministic visual atmosphere for the outdoor Reserve rooms.
## It does not place collision, change creature AI, grant items, or write saves.
## Real terrain/lantern artwork from Muse can replace this presentation layer.
##
## Uses only cheap canvas primitives and at most six pooled PointLight2D nodes.
## Most visual updates run at 20 Hz, reducing work on Android devices.

@export var bounds: Rect2 = Rect2(-1280, -360, 2560, 720)
@export var seed_value: int = 117
@export_range(0, 64, 1) var mote_count: int = 44
@export var lantern_positions: PackedVector2Array = PackedVector2Array()

const MOTE_COLOR := Color(0.73, 0.91, 0.67)
const GOLD_COLOR := Color(1.0, 0.72, 0.35)
const AMBER_COLOR := Color(0.91, 0.49, 0.20)
const POST_COLOR := Color(0.18, 0.17, 0.15)
const UPDATE_INTERVAL := 0.05

var _motes: Array[Dictionary] = []
var _lamps: Array[PointLight2D] = []
var _clock: Node = null
var _time_seconds: float = 0.0
var _draw_wait: float = 0.0
var _current_minutes: float = 540.0

static var _radial_light: GradientTexture2D = null

func _ready() -> void:
	z_as_relative = false
	z_index = -1750 # Above garden soil, behind real tree canopies and actors.
	_clock = get_parent().get_node_or_null("ReserveClock")
	_generate_motes()
	_create_lanterns()
	_sync_clock()
	_update_lighting()
	queue_redraw()

func _process(delta: float) -> void:
	if delta <= 0.0:
		return
	_time_seconds += delta
	_draw_wait += delta
	if _draw_wait < UPDATE_INTERVAL:
		return
	_draw_wait = fposmod(_draw_wait, UPDATE_INTERVAL)
	_sync_clock()
	_update_lighting()
	queue_redraw()

func _sync_clock() -> void:
	if _clock != null and is_instance_valid(_clock) and _clock.has_method("get_time_of_day"):
		_current_minutes = float(_clock.call("get_time_of_day"))

## Day=0.12; dusk ramps in; night=1; dawn slowly fades.
## Calendar/time tuning stays with ReserveClock; this only reacts to it.
static func glow_for_minutes(minutes: float) -> float:
	var m := fposmod(minutes, 1440.0)
	if m < 300.0:
		return 1.0
	if m < 420.0:
		return lerpf(1.0, 0.12, (m - 300.0) / 120.0)
	if m < 1020.0:
		return 0.12
	if m < 1170.0:
		return lerpf(0.12, 1.0, (m - 1020.0) / 150.0)
	return 1.0

static func mote_opacity(minutes: float) -> float:
	return 0.14 + 0.86 * glow_for_minutes(minutes)

func _generate_motes() -> void:
	_motes.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for i in range(mote_count):
		var p := Vector2(
			rng.randf_range(bounds.position.x + 28.0, bounds.end.x - 28.0),
			rng.randf_range(bounds.position.y + 36.0, bounds.end.y - 24.0))
		_motes.append({
			"home": p,
			"phase": rng.randf_range(0.0, TAU),
			"speed": rng.randf_range(0.30, 0.84),
			"radius": rng.randf_range(1.3, 2.7),
			"twinkle": rng.randf_range(0.7, 1.65),
			"drift_x": rng.randf_range(6.0, 20.0),
			"drift_y": rng.randf_range(5.0, 14.0),
		})

## Pure evaluation used by tests; no per-frame randomness or teleporting.
static func sample_mote(mote: Dictionary, elapsed: float) -> Vector2:
	var origin: Vector2 = mote.get("home", Vector2.ZERO)
	var phase := float(mote.get("phase", 0.0))
	var speed := float(mote.get("speed", 0.5))
	return origin + Vector2(
		sin(elapsed * speed + phase) * float(mote.get("drift_x", 12.0)),
		sin(elapsed * speed * 0.67 + phase * 1.51) * float(mote.get("drift_y", 9.0)))

static func _create_radial_texture() -> GradientTexture2D:
	if _radial_light != null:
		return _radial_light
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1.0, 0.95, 0.81, 0.95))
	gradient.set_color(1, Color(1.0, 0.68, 0.27, 0.0))
	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.width = 128
	tex.height = 128
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	_radial_light = tex
	return tex

func _create_lanterns() -> void:
	for lamp in _lamps:
		if is_instance_valid(lamp):
			lamp.queue_free()
	_lamps.clear()
	var tex := _create_radial_texture()
	for i in range(mini(lantern_positions.size(), 6)):
		var light := PointLight2D.new()
		light.name = "ReserveLanternLight%d" % i
		light.position = lantern_positions[i] + Vector2(0.0, -21.0)
		light.texture = tex
		light.texture_scale = 2.9
		light.color = GOLD_COLOR
		light.energy = 0.30
		light.shadow_enabled = false
		add_child(light)
		_lamps.append(light)

func _update_lighting() -> void:
	var amount := glow_for_minutes(_current_minutes)
	for i in range(_lamps.size()):
		var lamp := _lamps[i]
		if is_instance_valid(lamp):
			# Subtle deterministic flicker; not a flashing gameplay signal.
			lamp.energy = (0.14 + amount * 0.72) * (
				0.965 + 0.035 * sin(_time_seconds * 2.7 + float(i) * 1.9))

func _draw() -> void:
	var glow := glow_for_minutes(_current_minutes)
	for lamp_pos in lantern_positions:
		_draw_lantern(lamp_pos, glow)
	var visible := mote_opacity(_current_minutes)
	for mote in _motes:
		var p := sample_mote(mote, _time_seconds)
		# Each mote breathes at its own slow frequency.
		var shimmer := 0.62 + 0.38 * sin(
			_time_seconds * float(mote["twinkle"]) * 3.1 + float(mote["phase"]))
		var strength := clampf(visible * shimmer, 0.0, 1.0)
		var radius := float(mote["radius"])
		var halo := MOTE_COLOR
		halo.a = 0.12 * strength
		var core := MOTE_COLOR
		core.a = 0.53 * strength
		draw_circle(p, radius * 3.5, halo)
		draw_circle(p, radius, core)

func _draw_lantern(p: Vector2, glow: float) -> void:
	# No solid color block or scenery cut-out: only a modest lantern glyph
	# at a story landmark, ready to swap for an approved Muse sprite.
	draw_line(p + Vector2(0, 20), p + Vector2(0, -19), POST_COLOR, 5.0, true)
	draw_line(p + Vector2(-10, -19), p + Vector2(10, -19), POST_COLOR, 4.0, true)
	draw_line(p + Vector2(0, -19), p + Vector2(0, -24), POST_COLOR, 3.0, true)
	var halo := AMBER_COLOR
	halo.a = 0.10 + glow * 0.16
	var amber := GOLD_COLOR
	amber.a = 0.30 + glow * 0.65
	draw_circle(p + Vector2(0, -17), 20.0, halo)
	draw_circle(p + Vector2(0, -17), 5.5, amber)
	draw_circle(p + Vector2(-1, -18), 2.3, Color(1.0, 0.94, 0.73, 0.82))

func get_lantern_count() -> int:
	return _lamps.size()

func get_mote_count() -> int:
	return _motes.size()
