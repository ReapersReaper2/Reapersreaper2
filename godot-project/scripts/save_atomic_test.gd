extends SceneTree
const Save := preload("res://scripts/save_system.gd")
const SLOT := 94

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var ss = Save.new()
	root.add_child(ss)
	ss.delete_save(SLOT)
	var tmp := "user://saves/save_94.json.tmp"
	var state := Save.default_save()
	state["flags"]["marker"] = 1
	assert(ss.save_game(SLOT, state))
	assert(not FileAccess.file_exists(tmp))
	state["flags"]["marker"] = 2
	assert(ss.save_game(SLOT, state))
	assert(int(ss.load_game(SLOT)["flags"]["marker"]) == 2)
	assert(not FileAccess.file_exists(tmp))
	ss.delete_save(SLOT)
	print("[SAVE ATOMIC] PASS")
	quit(0)
