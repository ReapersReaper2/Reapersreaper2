extends Node2D
## Shika Hunters boss fight controller (GD4, the Ascent).
## Two hunters, 80 Vigor each. Coordinated alternating rhythm: one hunter
## is ACTIVE per cycle and attacks while the other circles; they tag out
## after every attack cycle. One dies -> the survivor enrages (faster).
##
## NOTE: intentionally no class_name (project convention).
## Pattern: wave_spawner.gd (fight phases, player-death reset).

signal fight_started
signal fight_won
signal fight_reset

const HunterScript := preload("res://scripts/shika_hunter.gd")

const VICTORY_FLAG := "gd4_shika_defeated"
const TRIGGER_NAME := "ShikaBoss"

enum Phase { IDLE, INTRO, FIGHTING, WON }

var game_state = null  # GameState autoload, or injected (tests)

var _phase: int = Phase.IDLE
var _hunters: Array = []
var _active_idx: int = 0
var _cycle_t: float = 0.0
var _cycle_len: float = 3.2  # seconds per attack cycle before tag-out
var _player = null
var _trigger = null
var _waiting_for_dialogue: bool = false
var _arena_center: Vector2 = Vector2.ZERO


func _ready() -> void:
	if game_state == null and is_inside_tree():
		game_state = get_node_or_null("/root/GameState")
	_arena_center = global_position
	_trigger = get_parent().get_node_or_null(TRIGGER_NAME) if get_parent() != null else null
	if _trigger != null and _trigger.has_signal("activated"):
		_trigger.activated.connect(_on_trigger_activated)
	_resolve_player()


func _resolve_player() -> void:
	if _player != null and is_instance_valid(_player):
		return
	if not is_inside_tree():
		return
	_player = get_tree().get_first_node_in_group("player")
	if _player != null and _player.has_signal("player_died"):
		if not _player.player_died.is_connected(_on_player_died):
			_player.player_died.connect(_on_player_died)


func _physics_process(delta: float) -> void:
	_resolve_player()
	if _waiting_for_dialogue:
		if _trigger == null or not _trigger.has_method("is_dialogue_open") or not _trigger.is_dialogue_open():
			_waiting_for_dialogue = false
			_begin_intro()
		return
	if _phase == Phase.FIGHTING:
		_cycle_t += delta
		if _cycle_t >= _cycle_len:
			_cycle_t = 0.0
			_tag_out()
		# Keep the active hunter attacking.
		var h = _hunters[_active_idx] if _active_idx < _hunters.size() else null
		if h != null and is_instance_valid(h) and h.is_alive():
			h.begin_attack_cycle()


func _on_trigger_activated(_obj) -> void:
	if _phase != Phase.IDLE:
		return
	if game_state != null and game_state.has_method("get_flag"):
		if bool(game_state.get_flag(VICTORY_FLAG)):
			return
	_waiting_for_dialogue = true


func _begin_intro() -> void:
	_spawn_hunters()
	_phase = Phase.INTRO
	_cycle_t = 0.0
	fight_started.emit()
	# Brief beat, then the rhythm starts.
	await get_tree().create_timer(1.2).timeout
	if _phase == Phase.INTRO:
		_phase = Phase.FIGHTING
		_activate_hunter(0)


func _spawn_hunters() -> void:
	_clear_hunters()
	for i in 2:
		var h: CharacterBody2D = HunterScript.new()
		h.position = _arena_center + Vector2(-160.0 + 320.0 * i, -120.0)
		add_child(h)
		h.died.connect(_on_hunter_died)
		_hunters.append(h)
	_active_idx = 0


func _clear_hunters() -> void:
	for h in _hunters:
		if is_instance_valid(h):
			h.queue_free()
	_hunters.clear()


func _activate_hunter(idx: int) -> void:
	_active_idx = idx
	for i in _hunters.size():
		var h = _hunters[i]
		if is_instance_valid(h):
			h.active = (i == idx) and h.is_alive()
			h.set_stance(not h.active)


func _tag_out() -> void:
	# Find the next living hunter that isn't active: the tag-out.
	var next := -1
	for i in _hunters.size():
		var h = _hunters[i]
		if is_instance_valid(h) and h.is_alive() and i != _active_idx:
			next = i
			break
	if next >= 0:
		_activate_hunter(next)


func _on_hunter_died(hunter) -> void:
	var alive: Array = []
	for h in _hunters:
		if is_instance_valid(h) and h.is_alive():
			alive.append(h)
	if alive.is_empty():
		_win()
	elif alive.size() == 1:
		# Survivor enrages and takes every cycle.
		alive[0].enrage()
		_active_idx = _hunters.find(alive[0])
		_activate_hunter(_active_idx)
		_cycle_len = 2.2


func _win() -> void:
	_phase = Phase.WON
	if game_state != null and game_state.has_method("set_flag"):
		game_state.set_flag(VICTORY_FLAG, true)
	if _trigger != null:
		_trigger.set_deferred("monitoring", false)
		_trigger.set_deferred("monitorable", false)
	fight_won.emit()


func _on_player_died() -> void:
	if _phase != Phase.FIGHTING and _phase != Phase.INTRO:
		return
	# "It's a memory" — the fight resets, no game over.
	_phase = Phase.IDLE
	_clear_hunters()
	_active_idx = 0
	_cycle_t = 0.0
	_cycle_len = 3.2
	fight_reset.emit()
	# Auto-restart after a beat, like the P1 waves.
	await get_tree().create_timer(1.5).timeout
	if _phase == Phase.IDLE:
		_begin_intro()


## Test hook: force-start without the trigger.
func debug_start() -> void:
	_waiting_for_dialogue = false
	_begin_intro()


func is_fighting() -> bool:
	return _phase == Phase.FIGHTING or _phase == Phase.INTRO


func hunter_count() -> int:
	var n := 0
	for h in _hunters:
		if is_instance_valid(h) and h.is_alive():
			n += 1
	return n


func active_hunter_index() -> int:
	return _active_idx
