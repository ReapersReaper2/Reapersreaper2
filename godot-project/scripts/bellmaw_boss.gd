extends Node2D
## The Bellmaw boss controller (Cloudbloom Plateau, Act 2).
## PUZZLE-BOSS: no HP bar. Observation -> experiment -> resolution.
## "No combat. No roaring. No triumph. Only survival through understanding."
##
## Voice wiring (VERBATIM, 06b THE BELLMAW scenes — data/dialogue_06b.md):
## - Observe: MOLLOSAR "...Okay." then "Okay." (he says it twice — both wired)
## - Experiment fail (wrong stimulus): MOLLOSAR "No. Not that." (NEW, confirmed)
## - Bloom reveal: MOLLOSAR "...You."
## - Resolution: MOLLOSAR "...You'd have had something to say."
##
## LUNA IS ABSENT for this entire sequence (06b continuity lock, enforced
## by room_act2.gd). The three Luna Bellmaw lines in boss-voice-packs.md
## are SUPERSEDED and are NOT wired here. There is no Luna content in
## this script — assert it in the test.
##
## NOTE: intentionally no class_name (project convention).
## Pattern: shika_boss.gd (fight phases, player-death reset).

signal fight_started
signal experiment_advanced(stimulus: String)
signal experiment_failed(stimulus: String)
signal fight_reset

const TRIGGER_NAME := "BellmawPuzzle"

## Story flags (dialogue_06b.gd routes these).
const FLAG_PUZZLE := "bellmaw_puzzle"
const FLAG_DEFEATED := "bellmaw_defeated"

## Verbatim lines (06b THE BELLMAW). Do not paraphrase.
const LINE_OBSERVE_1 := "...Okay."
const LINE_OBSERVE_2 := "Okay."
const LINE_FAIL := "No. Not that."
const LINE_REVEAL := "...You."
const LINE_RESOLVE := "...You'd have had something to say."

const SPEAKER := "MOLLOSAR"

## Stimulus set, from 06b Scene 2 (verbatim order of attempts).
## Movement, sound, sight, stone: all "Nothing." The bloom turns it.
const STIMULUS_MOVEMENT := "movement"
const STIMULUS_SOUND := "sound"
const STIMULUS_SIGHT := "sight"
const STIMULUS_STONE := "stone"
const STIMULUS_BLOOM := "bloom"
const CORRECT_STIMULUS := STIMULUS_BLOOM

const BARK_MAX_SECONDS := 2.0  # textbox over the scene, never pauses

enum Phase { IDLE, OBSERVE, EXPERIMENT, REVEAL, RESOLVED }

var game_state = null  # GameState autoload, or injected (tests)

var _phase: int = Phase.IDLE
var _attempts: Array[String] = []
var _player = null
var _trigger = null


func _ready() -> void:
	if game_state == null and is_inside_tree():
		game_state = get_node_or_null("/root/GameState")
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
		if bool(game_state.get_flag(FLAG_DEFEATED)):
			return
	_set_flag(FLAG_PUZZLE)
	_begin_observe()


func _begin_observe() -> void:
	_phase = Phase.OBSERVE
	fight_started.emit()
	# He says it twice. Wire BOTH.
	_bark(LINE_OBSERVE_1)
	await get_tree().create_timer(1.5).timeout
	if _phase == Phase.OBSERVE:
		_bark(LINE_OBSERVE_2)
		_phase = Phase.EXPERIMENT


## Called by the room's stimulus interactables (movement/sound/sight/
## stone/bloom). Wrong stimulus -> fail line, stay in EXPERIMENT.
## Correct stimulus (the bloom) -> advance to REVEAL.
func offer_stimulus(stimulus: String) -> void:
	if _phase != Phase.EXPERIMENT:
		return
	_attempts.append(stimulus)
	if stimulus == CORRECT_STIMULUS:
		_phase = Phase.REVEAL
		experiment_advanced.emit(stimulus)
		_bark(LINE_REVEAL)
		_begin_resolution()
	else:
		experiment_failed.emit(stimulus)
		_bark(LINE_FAIL)


func _begin_resolution() -> void:
	# The satchel throw, the plunge, the silence — then the last line.
	await get_tree().create_timer(2.5).timeout
	if _phase == Phase.REVEAL:
		_bark(LINE_RESOLVE)
		await get_tree().create_timer(1.5).timeout
		_resolve()


func _resolve() -> void:
	_phase = Phase.RESOLVED
	_set_flag(FLAG_DEFEATED)
	if _trigger != null:
		_trigger.set_deferred("monitoring", false)
		_trigger.set_deferred("monitorable", false)


func _on_player_died() -> void:
	if _phase == Phase.IDLE or _phase == Phase.RESOLVED:
		return
	# "It's a memory" — the puzzle resets, no game over.
	_phase = Phase.IDLE
	_attempts.clear()
	fight_reset.emit()


func _set_flag(flag: String) -> void:
	if game_state != null and game_state.has_method("set_flag"):
		game_state.set_flag(flag, true)


## Non-pausing bark: textbox over the scene, auto-closes.
func _bark(text: String) -> void:
	if not is_inside_tree():
		return
	var box = get_tree().get_first_node_in_group("dialogue_box")
	if box == null or not box.has_method("start_dialogue"):
		return
	box.start_dialogue([{"type": "dialogue", "character": SPEAKER, "text": text}])
	var timer := get_tree().create_timer(BARK_MAX_SECONDS)
	timer.timeout.connect(_close_bark.bind(box))


func _close_bark(box) -> void:
	if is_instance_valid(box) and box.has_method("force_close"):
		box.force_close()


## Test hook: force-start without the trigger.
func debug_start() -> void:
	_begin_observe()


func is_active() -> bool:
	return _phase != Phase.IDLE and _phase != Phase.RESOLVED


func attempt_count() -> int:
	return _attempts.size()
