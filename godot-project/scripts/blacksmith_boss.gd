extends Node2D
## The Blacksmith boss fight controller (Ch9, boss-track) — SCAFFOLD.
##
## STATUS: voice packs are written (boss-voice-packs.md, story side) and
## park here until the fight code exists. No stats, movesets, phases, or
## arena logic were delivered in the story package for the Ch9 boss-track
## (build item #9, Q2 open — routed to Whit via Tucker). This scaffold
## holds the shape so the fight can be written the day the text lands.
##
## Pattern: harrow_boss.gd (HP-bar boss, damage gate, player-death reset).
## NOTE: intentionally no class_name (project convention).

signal fight_started
signal fight_won
signal fight_reset

const TRIGGER_NAME := "BlacksmithFight"

## TODO(Q2): replace with the delivered stat block when Whit's fight text
## lands. Placeholder values mirror harrow_boss.gd's shape only.
const MAX_VIGOR := 150  # TODO(Q2): locked stat block pending
const VICTORY_FLAG := "blacksmith_defeated"  # TODO(Q2): confirm flag name

enum Phase { IDLE, INTRO, FIGHTING, WON }

var game_state = null  # GameState autoload, or injected (tests)

var vigor: int = MAX_VIGOR
var _phase: int = Phase.IDLE
var _player = null
var _trigger = null
var _arena_center: Vector2 = Vector2.ZERO


func _ready() -> void:
	if game_state == null and is_inside_tree():
		game_state = get_node_or_null("/root/GameState")
	vigor = MAX_VIGOR
	_arena_center = global_position
	add_to_group("hittable")
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


func _on_trigger_activated(_obj) -> void:
	if _phase != Phase.IDLE:
		return
	if game_state != null and game_state.has_method("get_flag"):
		if bool(game_state.get_flag(VICTORY_FLAG)):
			return
	_begin_intro()


func _begin_intro() -> void:
	_phase = Phase.INTRO
	fight_started.emit()
	# TODO(Q2): intro beat per Whit's fight text (voice packs park here).
	await get_tree().create_timer(1.2).timeout
	if _phase == Phase.INTRO:
		_phase = Phase.FIGHTING


## TODO(Q2): movesets, phases, arena logic per the delivered fight text.
func take_hit(amount: int, _from_dir: Vector2) -> void:
	if _phase != Phase.FIGHTING:
		return
	vigor = maxi(0, vigor - amount)
	if vigor <= 0:
		_win()


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
	vigor = MAX_VIGOR
	fight_reset.emit()


## Test hook: force-start without the trigger.
func debug_start() -> void:
	_begin_intro()


func is_fighting() -> bool:
	return _phase == Phase.FIGHTING or _phase == Phase.INTRO
