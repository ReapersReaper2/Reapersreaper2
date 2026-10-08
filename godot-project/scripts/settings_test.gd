extends SceneTree
## Reaper's Reaper — settings_test.gd
##
## Headless test for the settings system (scripts/settings.gd):
## volume sliders drive AudioServer buses, settings persist across
## load/save, fullscreen toggle calls DisplayServer (guarded headless),
## reset restores defaults, vibration toggle flips the gate.
##
## Runs on the first _process frame (cold-tree _initialize pattern).

const SettingsScript := preload("res://scripts/settings.gd")

var _failures := 0
var _ran := false


func _check(name: String, cond: bool) -> void:
	if cond:
		print("  PASS: ", name)
	else:
		_failures += 1
		print("  FAIL: ", name)


func _process(_delta: float) -> bool:
	if _ran:
		return true
	_ran = true
	_run()
	print("[settings_test] failures: ", _failures)
	quit()
	return true


func _bus_db(bus_name: String) -> float:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return -999.0
	return AudioServer.get_bus_volume_db(idx)


func _run() -> void:
	# Start from a clean slate: delete any existing settings file.
	var cfg_path := "user://settings.cfg"
	if FileAccess.file_exists(cfg_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(cfg_path))
	SettingsScript._cache = {}

	# 1. Defaults load when no file exists.
	var s: Dictionary = SettingsScript.load_settings()
	_check("default master 80", int(s["master_volume"]) == 80)
	_check("default music 80", int(s["music_volume"]) == 80)
	_check("default sfx 80", int(s["sfx_volume"]) == 80)
	_check("default fullscreen true", bool(s["fullscreen"]) == true)
	_check("default vibration true", bool(s["vibration"]) == true)

	# 2. Buses exist after load (Master always, Music/SFX created).
	_check("master bus exists", AudioServer.get_bus_index("Master") >= 0)
	_check("music bus created", AudioServer.get_bus_index("Music") >= 0)
	_check("sfx bus created", AudioServer.get_bus_index("SFX") >= 0)

	# 3. Volume changes apply to the bus (80% -> ~-1.9db, 0% -> -80db).
	SettingsScript.set_setting("music_volume", 50)
	var db50 := _bus_db("Music")
	_check("50% maps to ~-6db", absf(db50 - linear_to_db(0.5)) < 0.01)
	SettingsScript.set_setting("sfx_volume", 0)
	_check("0% maps to -80db (mute)", _bus_db("SFX") <= -79.9)
	SettingsScript.set_setting("master_volume", 100)
	_check("100% maps to 0db", absf(_bus_db("Master")) < 0.01)

	# 4. Persistence: settings survive a cache clear + reload.
	SettingsScript.set_setting("music_volume", 33)
	SettingsScript.set_setting("vibration", false)
	SettingsScript._cache = {}
	var s2: Dictionary = SettingsScript.load_settings()
	_check("music persists", int(s2["music_volume"]) == 33)
	_check("vibration persists false", bool(s2["vibration"]) == false)
	_check("untouched keeps default", int(s2["sfx_volume"]) == 0)  # was set to 0 above

	# 5. Vibration gate.
	_check("vibration_enabled false", SettingsScript.vibration_enabled() == false)
	SettingsScript.set_setting("vibration", true)
	_check("vibration_enabled true", SettingsScript.vibration_enabled() == true)

	# 6. Fullscreen toggle doesn't crash headless (guarded internally).
	SettingsScript.set_setting("fullscreen", false)
	_check("fullscreen false persists", bool(SettingsScript.get_setting("fullscreen")) == false)
	SettingsScript.set_setting("fullscreen", true)
	_check("fullscreen true persists", bool(SettingsScript.get_setting("fullscreen")) == true)

	# 7. Reset restores defaults.
	SettingsScript.set_setting("master_volume", 10)
	SettingsScript.reset_defaults()
	var s3: Dictionary = SettingsScript.load_settings()
	_check("reset master", int(s3["master_volume"]) == 80)
	_check("reset vibration", bool(s3["vibration"]) == true)
	_check("reset applies bus", absf(_bus_db("Master") - linear_to_db(0.8)) < 0.01)

	# 8. UI overlay: builds, opens, closes, no errors.
	var panel = SettingsScript.new()
	root.add_child(panel)
	panel._ready()
	_check("panel built rows", panel._rows.size() >= 6)  # 3 sliders + vib + reset + back (+fullscreen)
	_check("panel starts closed", not panel.is_open())
	panel.open()
	_check("panel opens", panel.is_open() and panel.visible)
	panel.move_selection(1)
	_check("selection moves", panel._selected == 1)
	panel.close()
	_check("panel closes", not panel.is_open() and not panel.visible)
	panel.queue_free()

	# 9. Unknown keys degrade gracefully (null, not a crash).
	_check("unknown key null", SettingsScript.get_setting("nonexistent") == null)

	# Clean up the test settings file.
	if FileAccess.file_exists(cfg_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(cfg_path))
	SettingsScript._cache = {}
