extends SceneTree
## Guard against future-version saves being interpreted by an older game.
## godot --headless --path godot-project --script res://scripts/save_compat_test.gd

const SaveSystem := preload("res://scripts/save_system.gd")
const GameState := preload("res://scripts/game_state.gd")
const Title := preload("res://scripts/title_screen.gd")
const SLOT := 96

var checks := 0
var failed := 0
var routes: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var ss = SaveSystem.new()
	root.add_child(ss)
	var gs = GameState.new()
	gs.save_system = ss
	root.add_child(gs)
	gs.new_game()
	gs.set_current_slot(SLOT)
	ss.delete_save(SLOT)
	var path := "user://saves/save_%d.json" % SLOT
	DirAccess.make_dir_recursive_absolute("user://saves")
	var future := SaveSystem.default_save()
	future["save_version"] = SaveSystem.SAVE_VERSION + 1
	future["unrecognized_progress"] = {"rare_story_state": 777}
	var raw := JSON.stringify(future)
	var writer := FileAccess.open(path, FileAccess.WRITE)
	writer.store_string(raw)
	writer.close()
	_check(ss.has_save(SLOT), "future file is preserved in its original slot")
	_check(ss.load_game(SLOT).is_empty(), "future save version cannot be downgraded")
	_check(FileAccess.get_file_as_string(path) == raw,
		"rejected future save remains byte-for-byte intact")
	_check(gs.load_from_slot(SLOT) == false,
		"game state refuses to replace live playthrough with newer schema")
	_check(gs.get_current_slot() == SLOT, "rejecting a save leaves live slot unchanged")
	var title = Title.new()
	title.game_state = gs
	title.scene_changer = Callable(self, "_capture")
	root.add_child(title)
	title._slot = SLOT
	_check("requires newer game build" in title.slot_summary(SLOT),
		"slot summary explains why newer save cannot be continued")
	title._continue()
	_check(routes.is_empty(), "failed Continue does not silently boot prologue")
	_check(title._slot_summary != null and
		"SAVE COULD NOT BE LOADED" in title._slot_summary.text,
		"failed Continue visibly reports load failure")
	_check(FileAccess.get_file_as_string(path) == raw,
		"failed Continue never destroys the newer save")
	ss.delete_save(SLOT)
	if failed > 0:
		push_error("[SAVE COMPAT] %d/%d checks failed" % [failed, checks])
	else:
		print("[SAVE COMPAT] PASS %d checks" % checks)
	quit(1 if failed > 0 else 0)

func _capture(path: String) -> void:
	routes.append(path)

func _check(ok: bool, desc: String) -> void:
	checks += 1
	if not ok:
		failed += 1
		push_error("[SAVE COMPAT] " + desc)
