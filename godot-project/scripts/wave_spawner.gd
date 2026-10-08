extends Node2D
## Data-driven invader wave controller (P1 Bellhollow Bridge).
##
## NOTE: intentionally no class_name (project convention).
## Spawn points are child Marker2D nodes in the "invader_spawn" group.
## Room scripts call start_waves(); the spawner handles the rest.
##
## Wave dict format (tune freely — all keys optional except "count"):
##   {"count": 3, "hp": 2, "speed": 90.0, "damage": 1,
##    "spawn_delay": 1.6, "spawn_points": [0, 1, 2]}
## spawn_points are indices into the collected Marker2D list; omitted
## means "cycle through all of them".

signal wave_started(index: int)
signal wave_cleared(index: int)
signal all_waves_cleared
signal wave_reset(index: int)

const InvaderScene: PackedScene = preload("res://scenes/invader.tscn")

@export var waves: Array[Dictionary] = [
	{"count": 3, "hp": 2, "speed": 90.0, "damage": 1, "spawn_delay": 1.6},
	{"count": 4, "hp": 3, "speed": 100.0, "damage": 1, "spawn_delay": 1.2},
	{"count": 5, "hp": 3, "speed": 115.0, "damage": 1, "spawn_delay": 0.9},
]
## Pause before the first invader of wave 1 (lets the tutorial breathe).
@export var initial_delay: float = 4.0
## Breather between waves.
@export var breather_time: float = 3.0
## Pause before the current wave restarts after the player goes down.
@export var restart_delay: float = 1.0
## Where the player respawns on death (room scripts set this).
@export var player_reset_position: Vector2 = Vector2(-1000, 100)

enum Phase { IDLE, SPAWNING, FIGHTING, BREATHER, RESTARTING, DONE }

var game_state = null  # GameState autoload, or injected (tests)

var _phase: int = Phase.IDLE
var _wave_idx: int = -1
var _spawned: int = 0
var _alive: int = 0
var _spawn_t: float = 0.0
var _phase_t: float = 0.0
var _spawn_points: Array[Vector2] = []
var _invaders: Array = []
var _player = null


func _ready() -> void:
	if game_state == null and is_inside_tree():
		# Absolute-path lookup is illegal before the node is inside the
		# tree (headless -s harnesses); in-game this always resolves.
		game_state = get_node_or_null("/root/GameState")
	for node in get_children():
		if node is Marker2D and node.is_in_group("invader_spawn"):
			_spawn_points.append((node as Marker2D).global_position)
	if _spawn_points.is_empty():
		push_warning("wave_spawner: no invader_spawn markers found")
	_player = null
	_resolve_player()


func _resolve_player() -> void:
	if _player != null and is_instance_valid(_player):
		return
	# get_tree() is null before the node is inside the tree (headless -s
	# harnesses call _ready() explicitly); resolve lazily instead.
	if not is_inside_tree():
		return
	_player = get_tree().get_first_node_in_group("player")
	if _player != null and _player.has_signal("player_died"):
		if not _player.player_died.is_connected(_on_player_died):
			_player.player_died.connect(_on_player_died)


func start_waves() -> void:
	if _phase != Phase.IDLE:
		return
	_begin_wave(0, initial_delay)


func is_done() -> bool:
	return _phase == Phase.DONE


func alive_count() -> int:
	return _alive


func _begin_wave(idx: int, first_delay: float) -> void:
	_wave_idx = idx
	_spawned = 0
	_alive = 0
	_spawn_t = first_delay
	_phase = Phase.SPAWNING
	wave_started.emit(idx)
	print("[WAVE] wave ", idx + 1, "/", waves.size(), " started")


func _physics_process(delta: float) -> void:
	_resolve_player()
	match _phase:
		Phase.SPAWNING:
			_spawn_t -= delta
			if _spawn_t <= 0.0:
				_spawn_one()
				if _spawned >= _wave_count():
					_phase = Phase.FIGHTING
				else:
					_spawn_t = _wave_delay()
		Phase.BREATHER:
			_phase_t -= delta
			if _phase_t <= 0.0:
				var next: int = _wave_idx + 1
				_begin_wave(next, float((waves[next] as Dictionary).get("spawn_delay", 1.0)))
		Phase.RESTARTING:
			_phase_t -= delta
			if _phase_t <= 0.0:
				_begin_wave(_wave_idx, _wave_delay())
		Phase.FIGHTING:
			# Alive-count driven, not died-signal driven: invaders killed
			# while later ones are still spawning still clear the wave.
			if _alive <= 0 and _spawned >= _wave_count():
				_clear_wave()
		# IDLE/DONE: nothing.


func _wave_count() -> int:
	return int((waves[_wave_idx] as Dictionary).get("count", 0))


func _wave_delay() -> float:
	return float((waves[_wave_idx] as Dictionary).get("spawn_delay", 1.0))


func _wave_spawn_indices() -> Array:
	var idxs: Array = (waves[_wave_idx] as Dictionary).get("spawn_points", [])
	if idxs.is_empty():
		for i in range(_spawn_points.size()):
			idxs.append(i)
	return idxs


func _spawn_one() -> void:
	if _spawn_points.is_empty():
		push_warning("wave_spawner: cannot spawn, no spawn points")
		_phase = Phase.FIGHTING
		return
	var inv = InvaderScene.instantiate()
	var w: Dictionary = waves[_wave_idx]
	var idxs: Array = _wave_spawn_indices()
	var at: Vector2 = _spawn_points[int(idxs[_spawned % idxs.size()]) % _spawn_points.size()]
	inv.position = at
	inv.max_hp = int(w.get("hp", 3))
	inv.walk_speed = float(w.get("speed", 95.0))
	inv.damage = int(w.get("damage", 1))
	inv.target = _player
	add_child(inv)
	# Under -s test harnesses _ready() doesn't auto-fire; in-game it does.
	if not inv.is_node_ready():
		inv._ready()
	if not inv.died.is_connected(_on_invader_died):
		inv.died.connect(_on_invader_died)
	_invader_track(inv)
	_spawned += 1


func _invader_track(inv) -> void:
	_invader_untrack(inv)
	_invader_list().append(inv)
	_alive += 1


func _invader_untrack(inv) -> void:
	var list: Array = _invader_list()
	if list.has(inv):
		list.erase(inv)
		_alive = maxi(0, _alive - 1)


func _invader_list() -> Array:
	return _invaders


func _on_invader_died(inv) -> void:
	_invader_untrack(inv)
	# Wave-clear is checked in _physics_process (FIGHTING phase), not here.


func _clear_wave() -> void:
	wave_cleared.emit(_wave_idx)
	print("[WAVE] wave ", _wave_idx + 1, " cleared")
	if _wave_idx >= waves.size() - 1:
		_phase = Phase.DONE
		if game_state != null and game_state.has_method("set_flag"):
			game_state.set_flag("p1_bridge_cleared")
		_stats_waves_cleared()
		all_waves_cleared.emit()
		print("[WAVE] all waves cleared — p1_bridge_cleared set")
	else:
		_phase = Phase.BREATHER
		_phase_t = breather_time


## Player went down: no game over (the prologue is a memory and cannot be
## lost) — free the wave, restore vigor, put the player back at the wave
## start, and restart the current wave after a beat, under a quick fade.
func _on_player_died() -> void:
	if _phase == Phase.IDLE or _phase == Phase.DONE:
		return
	print("[WAVE] player down — resetting wave ", _wave_idx + 1)
	for inv in _invader_list().duplicate():
		if is_instance_valid(inv):
			inv.queue_free()
	_invader_list().clear()
	_alive = 0
	_spawned = 0
	if _player != null:
		if _player.has_method("heal_full"):
			_player.heal_full()
		_player.global_position = player_reset_position
		if "velocity" in _player:
			_player.velocity = Vector2.ZERO
	_play_fade()
	_phase = Phase.RESTARTING
	_phase_t = restart_delay
	wave_reset.emit(_wave_idx)


## Feed the achievement stat tracker (null-safe: headless tests have no Stats).
func _stats_waves_cleared() -> void:
	if not is_inside_tree():
		return
	var st = get_node_or_null("/root/Stats")
	if st != null and st.has_method("on_waves_cleared"):
		st.on_waves_cleared()


func _play_fade() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 40
	var rect := ColorRect.new()
	rect.color = Color(0, 0, 0, 0)
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(rect)
	get_tree().root.add_child(layer)
	var tw := create_tween()
	tw.tween_property(rect, "color:a", 1.0, 0.22)
	tw.tween_property(rect, "color:a", 0.0, 0.45)
	tw.tween_callback(layer.queue_free)
