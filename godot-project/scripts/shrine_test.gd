extends SceneTree
## Headless Lantern Shrine test: rest sequence, save write, heal, keeper
## achievement, range gating, repeatability, deferred save via dialogue box.
## Run: ./Godot_v4.3-stable_linux.x86_64 --headless --path <project> -s res://scripts/shrine_test.gd
## Uses throwaway slot 95 so real saves are never touched.
##
## NOTE: under -s, nodes added here are not inside the tree yet, so the test
## injects dependencies (shrine.game_state) and calls internals directly —
## the same pattern as wave_test / save_test.

const SLOT := 95

var _failures: Array[String] = []


class FakeBox extends Node:
	signal dialogue_finished
	var started: Array = []

	func start_dialogue(entries: Array, _start_index: int = 0) -> void:
		started = entries


func _check(name: String, cond: bool) -> void:
	if cond:
		print("  PASS: ", name)
	else:
		_failures.append(name)
		print("  FAIL: ", name)


func _make_stack() -> Array:
	var save_system_script = load("res://scripts/save_system.gd")
	var game_state_script = load("res://scripts/game_state.gd")
	var ach_script = load("res://scripts/achievements.gd")
	var ss = save_system_script.new()
	root.add_child(ss)
	var ach = ach_script.new()
	root.add_child(ach)
	var gs = game_state_script.new()
	gs.save_system = ss
	gs.achievements = ach
	root.add_child(gs)
	# Explicit _ready(): under -s the tree is cold, so scripts guard
	# every tree service internally.
	gs._ready()
	ach.game_state = gs
	return [ss, ach, gs]


func _make_shrine(gs, shrine_id: String):
	var shrine = (load("res://scenes/shrine.tscn") as PackedScene).instantiate()
	shrine.shrine_id = shrine_id
	shrine.game_state = gs
	root.add_child(shrine)
	shrine._ready()
	return shrine


func _make_player():
	var player = (load("res://scenes/player.tscn") as PackedScene).instantiate()
	root.add_child(player)
	player._ready()
	# Belt-and-suspenders: the tscn already carries groups=["player"],
	# but scene groups may not be registered while the tree is cold.
	if not player.is_in_group("player"):
		player.add_to_group("player")
	return player


func _initialize() -> void:
	print("=== SHRINE TEST ===")
	var stack: Array = _make_stack()
	var ss = stack[0]
	var ach = stack[1]
	var gs = stack[2]

	# 1. current_slot plumbing (default 1, settable).
	_check("default current_slot 1", gs.get_current_slot() == 1)
	gs.set_current_slot(SLOT)
	_check("set_current_slot", gs.get_current_slot() == SLOT)
	_check("default_save carries current_slot",
		int((load("res://scripts/save_system.gd") as GDScript).default_save().get("current_slot", 0)) == 1)
	ss.delete_save(SLOT)

	var shrine = _make_shrine(gs, "p1_1")
	var player = _make_player()

	# 2. Prompt hidden until the player is in range.
	_check("prompt hidden out of range", not (shrine.get_node("Prompt") as Label).visible)
	shrine._on_body_entered(player)
	_check("prompt visible in range", (shrine.get_node("Prompt") as Label).visible)

	# 3. Rest with no dialogue box: immediate save + flag + keeper + heal.
	player.vigor = 1
	shrine.rest()
	_check("save file written", ss.has_save(SLOT))
	_check("shrine flag set", gs.get_flag("shrine_p1_1"))
	_check("keeper achievement unlocked", ach.is_unlocked("keeper"))
	_check("vigor healed to full", player.vigor == player.vigor_max)
	var loaded: Dictionary = ss.load_game(SLOT)
	_check("save payload carries shrine flag",
		bool((loaded.get("flags", {}) as Dictionary).get("shrine_p1_1", false)))

	# 4. Repeatable: a second rest works.
	player.vigor = 2
	shrine.rest()
	_check("second rest re-saves", ss.has_save(SLOT))
	_check("second rest heals again", player.vigor == player.vigor_max)

	# 5. Deferred path: with a dialogue box, the save waits for dialogue_finished.
	var shrine2 = _make_shrine(gs, "p1_2")
	var fake := FakeBox.new()
	shrine2._dialogue_box = fake
	fake.dialogue_finished.connect(shrine2._on_dialogue_finished)
	shrine2._on_body_entered(player)
	ss.delete_save(SLOT)
	shrine2.rest()
	_check("dialogue started with rest line", fake.started.size() == 1)
	_check("no save before dialogue finishes", not ss.has_save(SLOT))
	fake.dialogue_finished.emit()
	_check("save written after dialogue", ss.has_save(SLOT))
	_check("deferred shrine flag set", gs.get_flag("shrine_p1_2"))

	# 6. Out-of-range E does nothing.
	var shrine3 = _make_shrine(gs, "p1_3")
	ss.delete_save(SLOT)
	var ev := InputEventAction.new()
	ev.action = "interact"
	ev.pressed = true
	shrine3._unhandled_input(ev)
	_check("out-of-range E writes no save", not ss.has_save(SLOT))
	_check("out-of-range prompt stays hidden", not (shrine3.get_node("Prompt") as Label).visible)

	# 7. heals=false variant: save still written, vigor untouched.
	var shrine4 = _make_shrine(gs, "p1_4")
	shrine4.heals = false
	shrine4._on_body_entered(player)
	player.vigor = 1
	shrine4.rest()
	_check("no-heal shrine still saves", ss.has_save(SLOT))
	_check("no-heal shrine leaves vigor", player.vigor == 1)
	_check("no-heal shrine sets its flag", gs.get_flag("shrine_p1_4"))

	# 8. Body exit hides the prompt again.
	shrine._on_body_exited(player)
	_check("prompt hidden after exit", not (shrine.get_node("Prompt") as Label).visible)

	# 9. Cleanup.
	ss.delete_save(SLOT)
	_check("slot cleaned up", not ss.has_save(SLOT))

	print("=== SHRINE TEST: %d failure(s) ===" % _failures.size())
	for f in _failures:
		print("  FAILED: ", f)
	quit(0 if _failures.is_empty() else 1)
