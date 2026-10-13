extends Node2D
## Reserve's visible day/night clock. Pure lighting and dusk signals only.
## Bonding resolution listens to dusk_started in a later sprint; this clock
## never awards captures or modifies the roster.
##
## Stored as an OPTIONAL scalar on the existing v3 save payload: older
## saves safely begin in daylight, no format change or migration needed.

signal phase_changed(phase: String)
signal phase_started(phase: String, day_number: int)
signal phase_ended(phase: String, day_number: int)
signal dusk_started(day_number: int)

@export_range(60.0, 3600.0, 1.0) var cycle_seconds: float = 720.0
@export_range(0.0, 24.0, 0.5) var starting_hour: float = 9.0
@export var show_clock: bool = true
@export var apply_world_tint: bool = true

const SAVE_KEY := "reserve_time_minutes"
const DAY_MINUTES := 1440.0
## PROPOSED durations from BOT-001's 2026-10-13 clock task. Awaiting Jenn
## ratification; changing each duration here is the only timing change needed.
const DAWN_SECONDS := 60.0
const DAY_SECONDS := 360.0
const DUSK_SECONDS := 120.0
const NIGHT_SECONDS := 180.0
const PROPOSED_CYCLE_SECONDS := DAWN_SECONDS + DAY_SECONDS + DUSK_SECONDS + NIGHT_SECONDS
## Existing visible game-clock boundaries are retained for save compatibility.
const DAWN_AT := 300.0 # 05:00
const DAY_AT := 420.0  # 07:00
const DUSK_AT := 1020.0 # 17:00
const NIGHT_AT := 1170.0 # 19:30
const NIGHT_LIGHT := Color(0.37, 0.42, 0.66)
const DAWN_LIGHT := Color(0.72, 0.64, 0.69)
const DAY_LIGHT := Color(1.00, 0.98, 0.91)
const DUSK_LIGHT := Color(0.80, 0.58, 0.59)

var _total_minutes: float = 540.0
var _phase: String = ""
var _last_save_minute: int = -1
var _world_tint: CanvasModulate = null
var _clock_label: Label = null
var _game_state: Node = null

func _ready() -> void:
	add_to_group("reserve_clock")
	_game_state = get_node_or_null("/root/GameState")
	_total_minutes = starting_hour * 60.0
	if _game_state != null:
		var saved: Variant = _game_state.get("state")
		if saved is Dictionary:
			_total_minutes = maxf(0.0, float(saved.get(SAVE_KEY, _total_minutes)))
	if apply_world_tint:
		_world_tint = CanvasModulate.new()
		_world_tint.name = "ReserveWorldTint"
		add_child(_world_tint)
	if show_clock:
		_build_hud()
	_update_presentation(true)

func _process(delta: float) -> void:
	if delta <= 0.0:
		return
	advance_seconds(delta)

## Headless-friendly deterministic advance. Four uneven real-time phases
## map onto the existing 24h display clock, preserving old saves and art.
## One complete cycle is exactly 720 real seconds with the proposed values.
func advance_seconds(seconds: float) -> void:
	if seconds <= 0.0 or cycle_seconds <= 0.0:
		return
	var left := seconds
	while left > 0.000001:
		var old_phase := get_phase()
		var boundary := _phase_end_total(_total_minutes)
		var speed := _phase_game_minutes(old_phase) / phase_duration_seconds(old_phase)
		var to_boundary := maxf(0.0, (boundary - _total_minutes) / speed)
		if left + 0.000001 < to_boundary:
			_total_minutes += left * speed
			left = 0.0
		else:
			left = maxf(0.0, left - to_boundary)
			_total_minutes = boundary
			phase_ended.emit(old_phase, get_day())
			_update_presentation(false)
			if get_phase() == "dusk":
				dusk_started.emit(get_day())
	_update_presentation(false)
	_store_progress()


## How much actual elapsed time one phase occupies. cycle_seconds remains
## an optional scene tuning multiplier, with 720s as the approved task's
## proposed default.
func phase_duration_seconds(phase_name: String) -> float:
	var proposed := PROPOSED_CYCLE_SECONDS
	match phase_name:
		"dawn":
			proposed = DAWN_SECONDS
		"day":
			proposed = DAY_SECONDS
		"dusk":
			proposed = DUSK_SECONDS
		"night":
			proposed = NIGHT_SECONDS
	return proposed * cycle_seconds / PROPOSED_CYCLE_SECONDS


static func _phase_game_minutes(phase_name: String) -> float:
	match phase_name:
		"dawn":
			return DAY_AT - DAWN_AT
		"day":
			return DUSK_AT - DAY_AT
		"dusk":
			return NIGHT_AT - DUSK_AT
	return DAY_MINUTES - NIGHT_AT + DAWN_AT


static func _phase_end_total(total_minutes: float) -> float:
	var m := fposmod(total_minutes, DAY_MINUTES)
	var start := total_minutes - m
	if m < DAWN_AT:
		return start + DAWN_AT
	if m < DAY_AT:
		return start + DAY_AT
	if m < DUSK_AT:
		return start + DUSK_AT
	if m < NIGHT_AT:
		return start + NIGHT_AT
	return start + DAY_MINUTES + DAWN_AT


## Neutral gameplay queries: Lullmother and encounter systems may subscribe
## without the clock implementing any capture/plant rules.
func get_phase_remaining_seconds() -> float:
	var phase_name := get_phase()
	var minutes_left := _phase_end_total(_total_minutes) - _total_minutes
	return maxf(0.0, minutes_left *
		phase_duration_seconds(phase_name) / _phase_game_minutes(phase_name))


func get_time_remaining_in_phase() -> float:
	return get_phase_remaining_seconds()


func get_phase_elapsed_seconds() -> float:
	return phase_duration_seconds(get_phase()) - get_phase_remaining_seconds()


func set_total_minutes(minutes: float) -> void:
	_total_minutes = maxf(0.0, minutes)
	_update_presentation(true)
	_store_progress()

func get_total_minutes() -> float:
	return _total_minutes

func get_day() -> int:
	return int(floor(_total_minutes / DAY_MINUTES)) + 1

func get_time_of_day() -> float:
	return fposmod(_total_minutes, DAY_MINUTES)

func get_phase() -> String:
	return phase_for(get_time_of_day())

static func phase_for(minutes: float) -> String:
	var m := fposmod(minutes, DAY_MINUTES)
	if m >= 300.0 and m < 420.0:
		return "dawn"
	if m >= 420.0 and m < 1020.0:
		return "day"
	if m >= 1020.0 and m < 1170.0:
		return "dusk"
	return "night"

static func light_for(minutes: float) -> Color:
	var m := fposmod(minutes, DAY_MINUTES)
	if m < 300.0:
		return NIGHT_LIGHT
	if m < 420.0:
		return NIGHT_LIGHT.lerp(DAWN_LIGHT, (m - 300.0) / 120.0)
	if m < 480.0:
		return DAWN_LIGHT.lerp(DAY_LIGHT, (m - 420.0) / 60.0)
	if m < 1020.0:
		return DAY_LIGHT
	if m < 1110.0:
		return DAY_LIGHT.lerp(DUSK_LIGHT, (m - 1020.0) / 90.0)
	if m < 1200.0:
		return DUSK_LIGHT.lerp(NIGHT_LIGHT, (m - 1110.0) / 90.0)
	return NIGHT_LIGHT

func _update_presentation(force_signal: bool) -> void:
	var new_phase := get_phase()
	if force_signal or new_phase != _phase:
		_phase = new_phase
		phase_changed.emit(_phase)
		phase_started.emit(_phase, get_day())
	if _world_tint != null:
		_world_tint.color = light_for(get_time_of_day())
	if _clock_label != null:
		var current: int = int(floor(get_time_of_day()))
		_clock_label.text = "RESERVE  ·  DAY %d  ·  %02d:%02d  %s" % [
			get_day(), current / 60, current % 60, new_phase.to_upper()]

func _store_progress() -> void:
	if _game_state == null:
		return
	var state: Variant = _game_state.get("state")
	if not (state is Dictionary):
		return
	# Saving once per in-game minute avoids rewriting dictionary values
	# every rendered frame. The save system persists the full payload.
	var minute := int(floor(_total_minutes))
	if minute != _last_save_minute:
		state[SAVE_KEY] = _total_minutes
		_last_save_minute = minute

func _exit_tree() -> void:
	# Preserve the exact fraction when leaving the room/refuge, not only
	# the last rounded minute (important when dusk is seconds away).
	if _game_state == null:
		return
	var state: Variant = _game_state.get("state")
	if state is Dictionary:
		state[SAVE_KEY] = _total_minutes


func _build_hud() -> void:
	var hud := CanvasLayer.new()
	hud.name = "ReserveClockHUD"
	hud.layer = 11
	add_child(hud)
	var panel := ColorRect.new()
	panel.color = Color(0.045, 0.065, 0.075, 0.80)
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.offset_left = -364.0
	panel.offset_right = -14.0
	panel.offset_top = 16.0
	panel.offset_bottom = 62.0
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(panel)
	_clock_label = Label.new()
	_clock_label.anchor_left = 1.0
	_clock_label.anchor_right = 1.0
	_clock_label.offset_left = -351.0
	_clock_label.offset_right = -18.0
	_clock_label.offset_top = 26.0
	_clock_label.offset_bottom = 53.0
	_clock_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_clock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_clock_label.add_theme_font_size_override("font_size", 17)
	_clock_label.add_theme_color_override("font_color", Color(0.93, 0.82, 0.64))
	hud.add_child(_clock_label)
