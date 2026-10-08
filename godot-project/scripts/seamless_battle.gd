extends Node2D
## SeamlessBattle — in-overworld wild battle layer (no scene change).
##
## Spawned by BattleManager.start_wild_battle(). It lives in the room the
## encounter happened in: dims the room slightly, shows the full battle UI
## in a CanvasLayer, spawns the wild creature's visual at the encounter
## spot, locks the player, and runs the unmodified battle.gd turn logic
## in embedded mode. On resolution (win/flee/lose) it dismisses the layer
## and unlocks the player — the player never left the room and is still
## standing at the same position.
##
## Boss and trainer battles keep the staged battle.tscn transition; this
## host is only ever used for wild encounters.
##
## NOTE: intentionally no class_name (project convention).

signal resolved(outcome: String)

const BattleScript := preload("res://scripts/battle.gd")

## Battle config dict (same shape BattleManager.pending uses).
var config: Dictionary = {}
var battle_manager = null  # BattleManager autoload or injected
var game_state = null  # GameState autoload or injected
## Test hook: forwarded to the embedded battle (skips tween waits).
var battle_fast_mode := false

var _battle = null
var _layer: CanvasLayer = null
var _player: Node = null
var _creature_visual: Node2D = null
var _done := false


func setup(cfg: Dictionary, bm, gs) -> void:
	config = cfg
	battle_manager = bm
	game_state = gs


func _ready() -> void:
	_lock_player()
	_spawn_creature_visual()
	_build_layer()
	_start_battle()


## Freeze the player's overworld movement and input for the battle.
func _lock_player() -> void:
	if is_inside_tree():
		_player = get_tree().get_first_node_in_group("player")
	if _player != null:
		if "move_locked" in _player:
			_player.move_locked = true
		if "input_locked" in _player:
			_player.input_locked = true


func _unlock_player() -> void:
	if _player != null and is_instance_valid(_player):
		if "move_locked" in _player:
			_player.move_locked = false
		if "input_locked" in _player:
			_player.input_locked = false
	_player = null


## The wild creature appears in the room where the encounter happened —
## this is the visual that makes the battle feel seamless rather than
## staged. Uses battle.gd's shared sprite-or-dot helper.
func _spawn_creature_visual() -> void:
	var cid := str(config.get("enemy_creature_id", "bellowscap"))
	var pos: Vector2 = config.get("return_pos", Vector2.ZERO)
	_creature_visual = BattleScript.make_creature_visual(
		cid, pos + Vector2(90, -70), Color(0.55, 0.75, 0.45), 56.0)
	_creature_visual.name = "WildCreatureVisual"
	add_child(_creature_visual)


## Dim overlay + embedded battle UI in screen space (CanvasLayer).
func _build_layer() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 100
	_layer.name = "SeamlessBattleLayer"
	add_child(_layer)
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0.0, 0.0, 0.0, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_layer.add_child(dim)
	_battle = BattleScript.new()
	_battle.name = "EmbeddedBattle"
	_battle.embedded_mode = true
	_battle.battle_config = config
	_battle.battle_manager = battle_manager
	_battle.game_state = game_state
	_battle.fast_mode = battle_fast_mode
	_battle.battle_resolved.connect(_on_battle_resolved)
	_layer.add_child(_battle)


func _start_battle() -> void:
	if _battle != null:
		print("[SEAMLESS] wild battle in-overworld vs ", config.get("enemy_creature_id"))


func _on_battle_resolved(outcome: String) -> void:
	if _done:
		return
	_done = true
	print("[SEAMLESS] resolved: ", outcome)
	resolved.emit(outcome)
	_teardown()


func _teardown() -> void:
	_unlock_player()
	if _creature_visual != null and is_instance_valid(_creature_visual):
		_creature_visual.queue_free()
	_creature_visual = null
	# Frees the CanvasLayer (dim + embedded battle) with this node.
	queue_free()


## Read-only state for tests: is a seamless battle currently displayed?
func is_active() -> bool:
	return not _done and _layer != null and is_instance_valid(_layer)
