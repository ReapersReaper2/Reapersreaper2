extends Node2D
## Mount Dragoni boss fight controller (Ch12, atop the mountain).
## Scripted multi-wave escalation: Oni -> dark reapers -> Shika,
## ending in a SCRIPTED LOSS. Victory is never a win state here —
## the encounter's terminal state is the scripted loss; player defeat
## falls through to the loss beat, never a game-over ("it's a memory").
##
## Spawning rides the room's WaveSpawner node (room_d2.tscn, P1 pattern):
## this controller owns the wave DATA (WAVES) and the bark/loss beats,
## the spawner owns the loop. Barks fire on the spawner's wave_started
## signal; all_waves_cleared falls through to the scripted loss.
##
## Wave barks are VERBATIM per act2-boss-text.md (Dragoni constraint).
## Blast trigger: no new line — 06b governs verbatim (LUNA: "MOLLOSAR —").
## Pressed-hard (armor fracture, 06b Scene 2): the room calls
## _on_pressed_hard() when the armor-fracture trigger fires.
##
## NOTE: intentionally no class_name (project convention).
## Pattern: shika_boss.gd (fight phases, player-death reset),
## wave_spawner.gd (data-driven wave dicts).

signal fight_started
signal fight_won        # unused by design: never emitted; kept for the shared boss contract
signal fight_reset
signal wave_started(index: int)
signal scripted_loss

const TRIGGER_NAME := "SummitBoss"
const SPAWNER_NAME := "WaveSpawner"

## Story flags (dialogue_06b.gd routes these; the room sets them too).
const FLAG_AMBUSH := "dragoni_ambush"
const FLAG_BLAST := "blast_supermove"
const FLAG_COMPLETE := "ch12_complete"

## Verbatim wave barks (act2-boss-text.md §1). Do not paraphrase.
const BARK_WAVE_1 := "Oni. Broken tusks, no clan marks. Nobody owns these."
const BARK_WAVE_2 := "Reapers — they're cutting at the vines. Someone taught them."
const BARK_WAVE_3 := "Hold the pattern. He tires. Everything tires."
const BARK_PRESSED_HARD := "Your chest — the armor's cracking —"
# Blast trigger: 06b governs verbatim (LUNA: "MOLLOSAR —"). No new line.

const BARK_SPEAKER_WAVE_1 := "LUNA"
const BARK_SPEAKER_WAVE_2 := "LUNA"
const BARK_SPEAKER_WAVE_3 := "ALDER"
const BARK_SPEAKER_PRESSED_HARD := "LUNA"

## Wave composition: counts/spawns per wave spec'd from the combat
## encounter spec; storyboard numbers land here when Whit locks them
## (Q5 open — these are spec-per-review placeholders, not canon).
## Fed to the room's WaveSpawner (wave_spawner.gd dict format).
const WAVES: Array[Dictionary] = [
	{"name": "oni", "count": 4, "hp": 3, "speed": 100.0, "damage": 1, "spawn_delay": 1.4},
	{"name": "dark_reapers", "count": 5, "hp": 4, "speed": 110.0, "damage": 1, "spawn_delay": 1.1},
	{"name": "shika", "count": 2, "hp": 80, "speed": 120.0, "damage": 2, "spawn_delay": 2.0},
]

const BARK_MAX_SECONDS := 2.0  # textbox over fight, combat never pauses

enum Phase { IDLE, INTRO, FIGHTING, SCRIPTED_LOSS }

var game_state = null  # GameState autoload, or injected (tests)
var achievements = null  # Achievements autoload, or injected (tests)

var _phase: int = Phase.IDLE
var _wave_idx: int = -1
var _pressed_hard_fired: bool = false
var _player = null
var _trigger = null
var _spawner = null
var _arena_center: Vector2 = Vector2.ZERO


func _ready() -> void:
	if game_state == null and is_inside_tree():
		game_state = get_node_or_null("/root/GameState")
	if achievements == null and is_inside_tree():
		achievements = get_node_or_null("/root/Achievements")
	_arena_center = global_position
	if get_parent() != null:
		_trigger = get_parent().get_node_or_null(TRIGGER_NAME)
		_spawner = get_parent().get_node_or_null(SPAWNER_NAME)
	if _trigger != null and _trigger.has_signal("activated"):
		_trigger.activated.connect(_on_trigger_activated)
	if _spawner != null:
		if _spawner.has_signal("wave_started"):
			_spawner.wave_started.connect(_on_spawner_wave_started)
		if _spawner.has_signal("all_waves_cleared"):
			_spawner.all_waves_cleared.connect(_on_spawner_all_cleared)
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
		if bool(game_state.get_flag(FLAG_COMPLETE)):
			return
	_set_flag(FLAG_AMBUSH)
	_begin_intro()


func _begin_intro() -> void:
	_phase = Phase.INTRO
	fight_started.emit()
	await get_tree().create_timer(1.0).timeout
	if _phase != Phase.INTRO:
		return
	if _spawner != null and _spawner.has_method("start_waves"):
		_spawner.waves = WAVES
		_spawner.start_waves()
	else:
		# Headless/test fallback: sequence without the spawner.
		_begin_wave(0)


## The room's WaveSpawner fired wave_started: bark the wave, mark it.
func _on_spawner_wave_started(idx: int) -> void:
	_begin_wave(idx)


## The room's WaveSpawner finished every wave: the loss beat, never a win.
func _on_spawner_all_cleared() -> void:
	_scripted_loss()


func _begin_wave(idx: int) -> void:
	_wave_idx = idx
	_phase = Phase.FIGHTING
	_pressed_hard_fired = false
	var bark := ""
	var speaker := ""
	match idx:
		0:
			bark = BARK_WAVE_1
			speaker = BARK_SPEAKER_WAVE_1
		1:
			bark = BARK_WAVE_2
			speaker = BARK_SPEAKER_WAVE_2
		2:
			bark = BARK_WAVE_3
			speaker = BARK_SPEAKER_WAVE_3
	_bark(speaker, bark)
	wave_started.emit(idx)


## Manual wave driver (tests / rooms without a spawner node).
func _on_wave_cleared() -> void:
	if _phase != Phase.FIGHTING:
		return
	if _wave_idx < WAVES.size() - 1:
		_begin_wave(_wave_idx + 1)
	else:
		_scripted_loss()


## Armor-fracture beat (06b Scene 2). The room calls this when the
## armor-fracture trigger fires. Fires once per wave, mid-fight.
func _on_pressed_hard() -> void:
	if _phase != Phase.FIGHTING or _pressed_hard_fired:
		return
	_pressed_hard_fired = true
	_bark(BARK_SPEAKER_PRESSED_HARD, BARK_PRESSED_HARD)


func _scripted_loss() -> void:
	if _phase == Phase.SCRIPTED_LOSS:
		return
	_phase = Phase.SCRIPTED_LOSS
	_set_flag(FLAG_BLAST)
	_set_flag(FLAG_COMPLETE)
	# The scythe BREAKS here (weapon swap: scythe -> father's longsword).
	if achievements != null and achievements.has_method("notify_scythe_break"):
		achievements.notify_scythe_break()
	if _trigger != null:
		_trigger.set_deferred("monitoring", false)
		_trigger.set_deferred("monitorable", false)
	scripted_loss.emit()


func _on_player_died() -> void:
	if _phase != Phase.FIGHTING and _phase != Phase.INTRO:
		return
	# "It's a memory" — fall through to the loss beat, never a game-over.
	_scripted_loss()


func _set_flag(flag: String) -> void:
	if game_state != null and game_state.has_method("set_flag"):
		game_state.set_flag(flag, true)


## Non-pausing bark: textbox over the fight, auto-closes, combat continues.
func _bark(speaker: String, text: String) -> void:
	if not is_inside_tree():
		return
	var box = get_tree().get_first_node_in_group("dialogue_box")
	if box == null or not box.has_method("start_dialogue"):
		return
	box.start_dialogue([{"type": "dialogue", "character": speaker, "text": text}])
	var timer := get_tree().create_timer(BARK_MAX_SECONDS)
	timer.timeout.connect(_close_bark.bind(box))


func _close_bark(box) -> void:
	if is_instance_valid(box) and box.has_method("force_close"):
		box.force_close()


## Test hook: force-start without the trigger.
func debug_start() -> void:
	_begin_intro()


func is_fighting() -> bool:
	return _phase == Phase.FIGHTING or _phase == Phase.INTRO


func current_wave() -> int:
	return _wave_idx


func in_scripted_loss() -> bool:
	return _phase == Phase.SCRIPTED_LOSS
