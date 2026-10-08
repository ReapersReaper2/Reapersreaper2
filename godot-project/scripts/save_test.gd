extends SceneTree
## Headless save-system test: round-trip, missing/corrupt handling, migration.
## Run: ./Godot_v4.3-stable_linux.x86_64 --headless --path <project> -s res://scripts/save_test.gd
## Uses throwaway slots 90-99 so real saves are never touched.
## (Autoloads are not loaded under -s, so scripts are instantiated via load().)

var _failures: Array[String] = []


func _check(name: String, cond: bool) -> void:
	if cond:
		print("  PASS: ", name)
	else:
		_failures.append(name)
		print("  FAIL: ", name)


func _init() -> void:
	print("=== SAVE SYSTEM TEST ===")
	var save_system_script = load("res://scripts/save_system.gd")
	var game_state_script = load("res://scripts/game_state.gd")
	var ss = save_system_script.new()
	ss.name = "SaveSystem"
	root.add_child(ss)
	var gs = game_state_script.new()
	gs.save_system = ss
	root.add_child(gs)
	# NOTE: under -s, _ready() does not auto-fire for nodes added in _init().
	# Invoke it explicitly to exercise the real production path.
	gs._ready()

	# 1. Default structure.
	var d: Dictionary = save_system_script.default_save()
	_check("default has save_version 2", int(d.get("save_version", 0)) == 2)
	_check("default player form 1", int((d["player"] as Dictionary).get("form", 0)) == 1)
	_check("default position room", str(((d["player"] as Dictionary)["position"] as Dictionary).get("room", "")) == "P1_BELLHOLLOW_BRIDGE")
	_check("default has flags/ledger/inventory/party", d.has("flags") and d.has("ledger") and d.has("inventory") and d.has("party"))

	# 2. GameState boots fresh via _ready().
	_check("gamestate starts at form 1", gs.get_form() == 1)
	_check("gamestate flag default false", gs.get_flag("met_luna") == false)

	# 3. Round trip through GameState.
	gs.set_form(3)
	gs.set_flag("met_luna")
	gs.set_position("C1_RIVER", 100.5, 200.25)
	gs.add_playtime(123.5)
	_check("save_to_slot(91)", gs.save_to_slot(91))
	_check("has_save(91)", gs.has_save(91))
	_check("has_save(99) false", not gs.has_save(99))
	# Mutate in-memory, then reload.
	gs.set_form(1)
	gs.clear_flag("met_luna")
	gs.state["playtime"] = 0.0
	_check("load_from_slot(91)", gs.load_from_slot(91))
	_check("form restored to 3", gs.get_form() == 3)
	_check("flag restored", gs.get_flag("met_luna") == true)
	var pos: Dictionary = gs.get_position()
	_check("position restored", str(pos.get("room", "")) == "C1_RIVER" and abs(float(pos.get("x", 0.0)) - 100.5) < 0.001)
	_check("playtime restored", abs(float(gs.state.get("playtime", 0.0)) - 123.5) < 0.001)

	# 4. Save info header.
	var info: Dictionary = ss.get_save_info(91)
	_check("info exists", bool(info.get("exists", false)))
	_check("info version 2", int(info.get("version", 0)) == 2)
	_check("info chapter prologue", str(info.get("chapter", "")) == "prologue")
	_check("info timestamp stamped", int(info.get("timestamp", 0)) > 0)
	var info_missing: Dictionary = ss.get_save_info(99)
	_check("info missing -> exists false", not bool(info_missing.get("exists", true)))

	# 5. Shrine + autosave API.
	_check("save_shrine(92)", gs.save_shrine(92))
	_check("chapter_autosave()", gs.chapter_autosave())
	_check("autosave at slot 0", ss.has_save(0))

	# 6. Missing file.
	_check("load missing -> empty dict", (ss.load_game(99) as Dictionary).is_empty())
	_check("load_from_slot missing -> false", not gs.load_from_slot(99))

	# 7. Corrupt file.
	var corrupt_path := "user://saves/save_98.json"
	DirAccess.make_dir_recursive_absolute("user://saves")
	var cf := FileAccess.open(corrupt_path, FileAccess.WRITE)
	cf.store_string("THIS IS NOT JSON {{{")
	cf.close()
	_check("load corrupt -> empty dict", (ss.load_game(98) as Dictionary).is_empty())

	# 8. Migration v1 -> v2: grants the party system to old saves.
	var v1: Dictionary = save_system_script.default_save()
	v1.erase("party")  # simulate a real v1 save, which predates parties
	var v2: Dictionary = ss.migrate_v1_to_v2(v1)
	_check("migration stamps version 2", int(v2.get("save_version", 0)) == 2)
	_check("migration preserves data", int((v2["player"] as Dictionary).get("form", 0)) == 1)
	var migrated_party: Array = v2.get("party", [])
	_check("migration grants starter party", migrated_party.size() == 1)
	_check("migration starter is snapling lv5", str((migrated_party[0] as Dictionary).get("creature_id", "")) == "snapling" and int((migrated_party[0] as Dictionary).get("level", 0)) == 5)
	# An existing party is never clobbered.
	var v1b: Dictionary = save_system_script.default_save()
	v1b["party"] = [{"creature_id": "bellmaw", "level": 12, "xp": 0, "current_hp": 5, "nickname": "", "ability_ids": []}]
	var v2b: Dictionary = ss.migrate_v1_to_v2(v1b)
	_check("migration keeps existing party", (v2b.get("party", []) as Array).size() == 1 and str(((v2b["party"] as Array)[0] as Dictionary).get("creature_id", "")) == "bellmaw")

	# 9. migrate() is a no-op on current version.
	var cur: Dictionary = ss.migrate(save_system_script.default_save())
	_check("migrate no-op on v2", int(cur.get("save_version", 0)) == 2)

	# 10. Delete + cleanup.
	_check("delete_save(91)", ss.delete_save(91))
	_check("has_save(91) false after delete", not ss.has_save(91))
	_check("delete missing -> false", not ss.delete_save(91))
	ss.delete_save(92)
	ss.delete_save(0)
	ss.delete_save(98)

	print("=== TEST DONE: %d failure(s) ===" % _failures.size())
	if not _failures.is_empty():
		print("failures: ", _failures)
	quit(1 if not _failures.is_empty() else 0)
