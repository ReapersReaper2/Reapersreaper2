extends SceneTree
## Regression for touchscreen pause/save reliability and overlay lifecycle.
## Run: godot --headless --path godot-project --script res://scripts/pause_menu_test.gd

const PauseMenu := preload("res://scripts/pause_menu.gd")

class StubState:
	extends Node
	var saved_slot: int = -1
	var save_ok: bool = true
	var location: Dictionary = {}
	func get_current_slot() -> int:
		return 3
	func save_to_slot(slot: int) -> bool:
		saved_slot = slot
		return save_ok
	func set_position(room: String, x: float, y: float) -> void:
		location = {"room": room, "x": x, "y": y}

class StubRoom:
	extends Node2D
	var room_id: String = "gd1"

class StubPanel:
	extends Node
	var opened: bool = true
	func is_open() -> bool:
		return opened

var _checks: int = 0
var _failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var state = StubState.new()
	root.add_child(state)
	var room = StubRoom.new()
	root.add_child(room)
	var player = Node2D.new()
	player.add_to_group("player")
	room.add_child(player)
	player.position = Vector2(310.0, -40.0)
	var menu = PauseMenu.new()
	menu.game_state = state
	root.add_child(menu)
	menu.open()
	_check(menu.is_open() and paused, "menu opens and pauses gameplay")
	menu.activate("save")
	_check(menu._save_succeeded and state.saved_slot == 3,
		"successful save reports success")
	_check(str(state.location.get("room", "")) == "gd1"
		and is_equal_approx(float(state.location.get("x", 0)), 310.0)
		and is_equal_approx(float(state.location.get("y", 0)), -40.0),
		"pause save captures current room and exact player position")
	_check("SAVED" in menu._save_button.text, "success text matches save result")
	state.save_ok = false
	menu.activate("save")
	_check(not menu._save_succeeded, "save failure is not reported as success")
	_check("SAVE FAILED" in menu._save_button.text, "failure is visible to player")
	# A nested journal/breeding overlay must own Escape instead of allowing
	# the pause menu to unfreeze the game underneath an interactive panel.
	for group_name in ["breeding_ui", "journal", "settings", "party_panel"]:
		var panel = StubPanel.new()
		panel.add_to_group(group_name)
		root.add_child(panel)
		var cancel = InputEventAction.new()
		cancel.action = "ui_cancel"
		cancel.pressed = true
		menu._input(cancel)
		_check(menu.is_open() and paused,
			"nested " + group_name + " prevents unpausing")
		root.remove_child(panel)
		panel.free()
	menu.close()
	_check(not menu.is_open() and not paused, "closing resumes gameplay")
	_check(menu.is_queued_for_deletion(), "closing frees stale pause menu group")
	var second = PauseMenu.new()
	second.game_state = state
	root.add_child(second)
	second.open()
	_check(second.is_open() and paused, "fresh menu opens for another pause")
	second.close()
	_check(not paused, "second pause resumes normally")
	if _failures > 0:
		push_error("[PAUSE MENU] %d/%d checks failed" % [_failures, _checks])
	else:
		print("[PAUSE MENU] PASS %d checks" % _checks)
	quit(1 if _failures > 0 else 0)

func _check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		push_error("[PAUSE MENU] " + message)
