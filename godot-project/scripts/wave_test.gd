extends SceneTree
## Headless wave-spawner verification: waves spawn correct counts, kills
## clear waves, the cleared flag sets after the final wave, player death
## resets the current wave, and the invader matches the hittable pattern.
##
## Run: Godot --headless --path <project> -s res://scripts/wave_test.gd

const SpawnerScript := preload("res://scripts/wave_spawner.gd")

var _frame: int = 0
var _player = null
var _spawner = null
var _fake_state = null

var _checks: Dictionary = {}
var _wave_started: Array = []
var _wave_cleared: Array = []
var _all_cleared: bool = false
var _wave_reset: Array = []
var _phase: String = "clear_test"


class FakeState extends RefCounted:
	var flags: Dictionary = {}

	func set_flag(f: String, v: bool = true) -> void:
		flags[f] = v

	func get_flag(f: String, d: bool = false) -> bool:
		return bool(flags.get(f, d))


func _typed_waves(raw: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for w in raw:
		out.append(w)
	return out


func _make_spawner(raw_waves: Array, dmg: int) -> Node2D:
	var sp = SpawnerScript.new()
	for i in range(3):
		var m := Marker2D.new()
		m.position = Vector2(-1200, -220 + 220 * i)
		m.add_to_group("invader_spawn")
		sp.add_child(m)
	root.add_child(sp)
	sp.waves = _typed_waves(raw_waves)
	sp.initial_delay = 0.05
	sp.breather_time = 0.1
	sp.restart_delay = 0.1
	sp.game_state = _fake_state
	# Under -s, _ready() does not auto-fire for nodes added here.
	sp._ready()
	sp.wave_started.connect(func(i: int) -> void: _wave_started.append(i))
	sp.wave_cleared.connect(func(i: int) -> void: _wave_cleared.append(i))
	sp.all_waves_cleared.connect(func() -> void: _all_cleared = true)
	sp.wave_reset.connect(func(i: int) -> void: _wave_reset.append(i))
	return sp


func _initialize() -> void:
	_fake_state = FakeState.new()
	var ps: PackedScene = load("res://scenes/player.tscn")
	_player = ps.instantiate()
	root.add_child(_player)
	_player.position = Vector2.ZERO
	_player._ready()

	_spawner = _make_spawner([
		{"count": 2, "hp": 1, "speed": 250.0, "damage": 0, "spawn_delay": 0.05},
		{"count": 1, "hp": 1, "speed": 250.0, "damage": 0, "spawn_delay": 0.05},
	], 0)
	_checks["spawn_points_found"] = _spawner._spawn_points.size() == 3
	_spawner.start_waves()
	print("[TEST] wave spawner test starting")


func _kill_all() -> void:
	for inv in _spawner._invader_list().duplicate():
		if is_instance_valid(inv) and inv.is_alive():
			inv.take_hit(99, Vector2.RIGHT)


func _physics_process(_delta: float) -> bool:
	_frame += 1

	if _phase == "clear_test":
		# Kill whatever is alive every frame — robust to spawn timing.
		if not _all_cleared:
			# Verify the hittable pattern on the first live invader seen.
			if not _checks.get("invader_hittable_group", false) \
					and not _spawner._invader_list().is_empty():
				var first = _spawner._invader_list()[0]
				_checks["invader_hittable_group"] = first.is_in_group("hittable")
				_checks["invader_layer_4"] = first.collision_layer == 4
				_checks["invader_targets_player"] = first.target == _player
			_kill_all()
		if _wave_started.has(0) and not _checks.get("wave1_spawned_2", false) \
				and _spawner._spawned >= 2:
			_checks["wave1_spawned_2"] = true
		if _wave_cleared.has(0) and not _checks.get("wave1_cleared", false):
			_checks["wave1_cleared"] = true
		if _wave_started.has(1) and not _checks.get("wave2_started", false):
			_checks["wave2_started"] = true
		if _all_cleared:
			_checks["all_waves_cleared"] = true
			_checks["flag_set"] = _fake_state.get_flag("p1_bridge_cleared")
			_checks["phase_done"] = _spawner.is_done()
			# Move to the death test with a fresh spawner.
			_spawner.queue_free()
			_wave_started.clear()
			_wave_reset.clear()
			_spawner = _make_spawner([
				{"count": 2, "hp": 5, "speed": 250.0, "damage": 1, "spawn_delay": 0.05},
			], 1)
			_spawner.start_waves()
			_phase = "death_test"

	elif _phase == "death_test":
		if _spawner._spawned >= 1 and not _checks.get("death_dealt", false):
			_checks["death_dealt"] = true
			_player.take_damage(99)
		if _wave_reset.has(0) and not _checks.get("death_reset", false):
			_checks["death_reset"] = true
			_checks["invaders_freed"] = _spawner._alive == 0 \
				and _spawner._invader_list().is_empty()
			_checks["vigor_restored"] = _player.vigor == _player.vigor_max
			_checks["player_teleported"] = _player.global_position == \
				_spawner.player_reset_position
		if _checks.get("death_reset", false) and _wave_started.has(0) \
				and _wave_started.size() >= 2 and not _checks.get("wave_restarted", false):
			_checks["wave_restarted"] = true
		if _checks.get("wave_restarted", false):
			_finish()

	if _frame >= 900 and not _checks.get("finished", false):
		print("[TEST] TIMEOUT — checks so far: ", _checks)
		_finish()
	return false


const EXPECTED: Array = [
	"spawn_points_found",
	"wave1_spawned_2",
	"invader_hittable_group",
	"invader_layer_4",
	"invader_targets_player",
	"wave1_cleared",
	"wave2_started",
	"all_waves_cleared",
	"flag_set",
	"phase_done",
	"death_dealt",
	"death_reset",
	"invaders_freed",
	"vigor_restored",
	"player_teleported",
	"wave_restarted",
]


func _finish() -> void:
	if _checks.get("finished", false):
		return
	_checks["finished"] = true
	var failed: Array = []
	for k in EXPECTED:
		if not bool(_checks.get(k, false)):
			failed.append(k)
	print("[TEST] wave_test checks: ", EXPECTED.size(), " expected")
	if failed.is_empty():
		print("[TEST] wave_test: ALL PASS")
	else:
		print("[TEST] wave_test FAILED: ", failed)
	quit(0 if failed.is_empty() else 1)
