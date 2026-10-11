extends Node2D
## Gravemaw witness controller (SQ1 Warrens, giant sloth camp).
## He does not fight — he witnesses. The arena runs the P1
## invader-wave pattern while the Gravemaw watches. The encounter
## ends per the scene text (06b SQ1 Scenes 4-6), never per a defeat:
## there is no HP bar, no attacks, no win state on the entity.
##
## "A sloth does not abandon another sloth." (06b Scene 4)
##
## NOTE: intentionally no class_name (project convention).
## Pattern: wave_spawner.gd owns the invader loop; this controller
## owns the witness presence and the encounter flag.

signal encounter_started
signal encounter_ended
signal wave_loop_done

const TRIGGER_NAME := "GravemawWitness"

## Story flag: the encounter is complete when the scene says so.
const FLAG_WITNESSED := "sq1_gravemaw_witnessed"

## Invader-wave loop, wave_spawner dict format (P1 pattern).
## Counts spec'd from the combat encounter spec; tune per storyboard.
const WAVES: Array[Dictionary] = [
	{"count": 3, "hp": 2, "speed": 80.0, "damage": 1, "spawn_delay": 1.8},
	{"count": 4, "hp": 3, "speed": 90.0, "damage": 1, "spawn_delay": 1.4},
	{"count": 5, "hp": 3, "speed": 100.0, "damage": 1, "spawn_delay": 1.1},
]

enum Phase { IDLE, WITNESSING, DONE }

var game_state = null  # GameState autoload, or injected (tests)

var _phase: int = Phase.IDLE
var _spawner = null
var _player = null
var _trigger = null


func _ready() -> void:
	if game_state == null and is_inside_tree():
		game_state = get_node_or_null("/root/GameState")
	_trigger = get_parent().get_node_or_null(TRIGGER_NAME) if get_parent() != null else null
	if _trigger != null and _trigger.has_signal("activated"):
		_trigger.activated.connect(_on_trigger_activated)
	_setup_spawner()
	_resolve_player()


func _setup_spawner() -> void:
	# Reuse the P1 invader-wave controller; it owns the loop.
	var spawner_script = load("res://scripts/wave_spawner.gd")
	_spawner = spawner_script.new()
	_spawner.waves = WAVES
	_spawner.game_state = game_state
	add_child(_spawner)
	if _spawner.has_signal("all_waves_cleared"):
		_spawner.all_waves_cleared.connect(_on_all_waves_cleared)


func _resolve_player() -> void:
	if _player != null and is_instance_valid(_player):
		return
	if not is_inside_tree():
		return
	_player = get_tree().get_first_node_in_group("player")
	if _player != null and _player.has_signal("player_died"):
		if not _player.player_died.is_connected(_on_player_died):
			_player.player_died.connect(_on_player_died)


func _on_trigger_activated(_obj) -> void:
	if _phase != Phase.IDLE:
		return
	if game_state != null and game_state.has_method("get_flag"):
		if bool(game_state.get_flag(FLAG_WITNESSED)):
			return
	_phase = Phase.WITNESSING
	encounter_started.emit()
	if _spawner != null and _spawner.has_method("start_waves"):
		_spawner.start_waves()


func _on_all_waves_cleared() -> void:
	if _phase != Phase.WITNESSING:
		return
	wave_loop_done.emit()
	# The scene text ends the encounter — not a defeat. The flag is the
	# terminal state; the room's 06b scene plays the verdict beat.
	_end_encounter()


func _end_encounter() -> void:
	_phase = Phase.DONE
	_set_flag(FLAG_WITNESSED)
	if _trigger != null:
		_trigger.set_deferred("monitoring", false)
		_trigger.set_deferred("monitorable", false)
	encounter_ended.emit()


func _on_player_died() -> void:
	if _phase != Phase.WITNESSING:
		return
	# "It's a memory" — the wave loop resets; the witness remains.
	_phase = Phase.IDLE
	if _spawner != null:
		_spawner.queue_free()
		_setup_spawner()


func _set_flag(flag: String) -> void:
	if game_state != null and game_state.has_method("set_flag"):
		game_state.set_flag(flag, true)


## Test hook: force-start without the trigger.
func debug_start() -> void:
	_on_trigger_activated(null)


func is_witnessing() -> bool:
	return _phase == Phase.WITNESSING


func is_done() -> bool:
	return _phase == Phase.DONE
