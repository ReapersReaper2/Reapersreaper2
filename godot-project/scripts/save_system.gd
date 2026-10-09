extends Node
## JSON save system for Reaper's Reaper.
##
## NOTE: intentionally no class_name — Godot 4.3 errors when a class_name
## matches its autoload name ("hides an autoload singleton"). This script
## is registered as the "SaveSystem" autoload, so game code calls
## SaveSystem.save_game(...) etc. directly on the singleton.
##
## - Saves live at user://saves/save_<slot>.json. Steam Cloud (M5) just
##   points at user://saves/ — no path changes needed later.
## - Slot 0 is the chapter autosave; slots 1-3 are manual Lantern Shrine saves.
## - Every payload carries top-level "save_version". load_game() migrates
##   older saves forward through migrate_vN_to_vM() before returning.
## - Gameplay code goes through GameState; nothing else touches files.
##
## Registered as an autoload (project.godot) ahead of GameState.

const SAVE_VERSION := 3
const SAVE_DIR := "user://saves"
const AUTOSAVE_SLOT := 0
const MANUAL_SLOTS: Array[int] = [1, 2, 3]

const StatsScript := preload("res://scripts/stats.gd")
const PartyScript := preload("res://scripts/party.gd")


## Steam Cloud (M5+): point Steam's cloud sync at the OS-resolved
## user://saves/ directory — get_save_dir() returns the Godot path,
## ProjectSettings.globalize_path() resolves it to an absolute path for
## the Steamworks API. No save-path changes needed: the game always
## reads/writes through SAVE_DIR, and Steam just mirrors the folder.
## Auto-Cloud root patterns: saves/save_*.json
func get_save_dir() -> String:
	return SAVE_DIR


func _slot_path(slot: int) -> String:
	return "%s/save_%d.json" % [SAVE_DIR, slot]


## Canonical fresh-save structure. GameState.new_game() starts from this.
static func default_save() -> Dictionary:
	return {
		"save_version": SAVE_VERSION,
		"chapter": "prologue",
		"playtime": 0.0,
		"timestamp": 0,
		"current_slot": 1,
		"player": {
			"form": 1,
			"vigor": 3,
			"vigor_max": 3,
			"bloom": 0,
			"weapon": "scythe",
			"power_source": "armor",
			"position": {"room": "P1_BELLHOLLOW_BRIDGE", "x": 0.0, "y": 0.0},
		},
		"flags": {},
		"ledger": {"bounties": [], "forms": [], "creatures": [], "weapons": ["scythe"], "achievements": []},
		"inventory": {},
		"party": [],
		"stats": StatsScript.default_stats(),
		# Step clock (spec §2/§3): placeholder sentinels — GameState.new_game()
		# upgrades these to a real run_id/started_at via StepDriver.reset_run().
		"run": {"run_id": "", "started_at": 0, "steps_total": 0},
	}


## Write data to a slot. Stamps save_version + timestamp. Returns success.
func save_game(slot: int, data: Dictionary) -> bool:
	var payload: Dictionary = data.duplicate(true)
	payload["save_version"] = SAVE_VERSION
	payload["timestamp"] = int(Time.get_unix_time_from_system())
	if DirAccess.make_dir_recursive_absolute(SAVE_DIR) != OK:
		push_error("SaveSystem: could not create save dir %s" % SAVE_DIR)
		return false
	var path := _slot_path(slot)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("SaveSystem: cannot write %s (err %d)" % [path, FileAccess.get_open_error()])
		return false
	file.store_string(JSON.stringify(payload, "\t"))
	file.close()
	return true


## Read a slot. Returns {} when missing or corrupt (error printed).
## Migrates older save_versions forward before returning.
func load_game(slot: int) -> Dictionary:
	var path := _slot_path(slot)
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("SaveSystem: cannot read %s (err %d)" % [path, FileAccess.get_open_error()])
		return {}
	var text := file.get_as_text()
	file.close()
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("SaveSystem: corrupt save at %s (JSON parse failed)" % path)
		return {}
	return migrate(parsed)


func has_save(slot: int) -> bool:
	return FileAccess.file_exists(_slot_path(slot))


## Delete a slot. Returns false when nothing was there.
func delete_save(slot: int) -> bool:
	var path := _slot_path(slot)
	if not FileAccess.file_exists(path):
		return false
	if DirAccess.remove_absolute(path) != OK:
		push_error("SaveSystem: cannot delete %s" % path)
		return false
	return true


## Lightweight header read (no migration): for save-slot UI.
func get_save_info(slot: int) -> Dictionary:
	var info := {
		"exists": false, "version": 0, "playtime": 0.0,
		"chapter": "", "timestamp": 0,
	}
	var path := _slot_path(slot)
	if not FileAccess.file_exists(path):
		return info
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return info
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return info
	var data: Dictionary = parsed
	info["exists"] = true
	info["version"] = int(data.get("save_version", 0))
	info["playtime"] = float(data.get("playtime", 0.0))
	info["chapter"] = str(data.get("chapter", ""))
	info["timestamp"] = int(data.get("timestamp", 0))
	return info


## Manual save at a Lantern Shrine (shrines wire to this later).
func save_shrine(slot: int, data: Dictionary) -> bool:
	return save_game(slot, data)


## Chapter autosave (always slot 0).
func chapter_autosave(data: Dictionary) -> bool:
	return save_game(AUTOSAVE_SLOT, data)


## Run a loaded save forward to SAVE_VERSION through the migration chain.
## Unversioned (pre-v1) saves are treated as v1.
func migrate(data: Dictionary) -> Dictionary:
	var version := int(data.get("save_version", 1))
	while version < SAVE_VERSION:
		var before := version
		match version:
			1:
				data = migrate_v1_to_v2(data)
			2:
				data = migrate_v2_to_v3(data)
			_:
				push_error("SaveSystem: no migration path from save v%d" % version)
				break
		version = int(data.get("save_version", before))
		if version <= before:
			push_error("SaveSystem: migration v%d did not advance save_version" % before)
			break
	return data


## v1 -> v2: grant the party system. v1 saves predate parties, so a save
## with no "party" key gets the starter (snapling lv5, full HP). Never
## silently drop player data: an existing party (even empty) is left alone.
func migrate_v1_to_v2(data: Dictionary) -> Dictionary:
	if not data.has("party"):
		data["party"] = [PartyScript.make_starter_entry()]
	data["save_version"] = 2
	return data


## v2 -> v3: grant the run section (StepDriver basis, spec §3/C4).
## v2 saves predate the step driver, so a save with no "run" key gets the
## placeholder (empty run_id sentinel, upgraded to a real identity by
## StepDriver.ensure_run on load — steps start at 0 for pre-driver saves;
## no retroactive step invention). Never overwrites a valid existing run.
## A malformed run section gets field-wise repair in place (per-field
## definitions from spec §2/C3) — a valid steps_total is never reset.
##
## NOTE: SaveSystem deliberately does NOT preload StepDriver here.
## Identity generation lives at the GameState/StepDriver layer (avoids a
## preload-cycle risk; keeps the "SaveSystem sole file writer, gameplay
## through GameState" boundary). Non-static like migrate_v1_to_v2.
func migrate_v2_to_v3(data: Dictionary) -> Dictionary:
	var run = data.get("run", null)
	if not (run is Dictionary):
		data["run"] = {"run_id": "", "started_at": 0, "steps_total": 0}
	else:
		var r: Dictionary = run
		if not (r.get("run_id", "") is String) or (r.get("run_id", "") as String).is_empty():
			r["run_id"] = ""
		if not (r.get("started_at", -1) is int) or int(r.get("started_at", -1)) < 0:
			r["started_at"] = 0
		if not (r.get("steps_total", -1) is int) or int(r.get("steps_total", -1)) < 0:
			r["steps_total"] = 0
	data["save_version"] = 3
	return data
