extends CanvasLayer
## Reaper's Reaper — settings/options screen.
##
## NOTE: intentionally no class_name (project convention — see save_system.gd).
## Code-built UI (pause_menu.gd pattern). Master/Music/SFX volume sliders
## wired to AudioServer buses (Music/SFX buses are created at runtime if
## missing). Fullscreen toggle (desktop only), controller vibration toggle,
## reset-to-defaults. Persists to user://settings.cfg (global, not per-save).
## Keyboard: up/down move, left/right adjust sliders, Enter toggles/activates,
## Esc backs out. Opened from the title screen or over the pause menu.

signal closed

const SETTINGS_PATH := "user://settings.cfg"

const DEFAULTS := {
	"master_volume": 80,
	"music_volume": 80,
	"sfx_volume": 80,
	"fullscreen": true,
	"vibration": true,
}

static var _cache: Dictionary = {}


## Load settings from disk (or defaults). Called once per run.
static func load_settings() -> Dictionary:
	if not _cache.is_empty():
		return _cache
	_cache = DEFAULTS.duplicate()
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		for key in DEFAULTS:
			_cache[key] = cfg.get_value("settings", key, DEFAULTS[key])
	_ensure_buses()
	_apply_volumes()
	_apply_fullscreen()
	return _cache


## Persist current settings to disk.
static func save_settings() -> void:
	var cfg := ConfigFile.new()
	for key in DEFAULTS:
		cfg.set_value("settings", key, _cache.get(key, DEFAULTS[key]))
	cfg.save(SETTINGS_PATH)


## Reset to defaults (applies + persists).
static func reset_defaults() -> void:
	_cache = DEFAULTS.duplicate()
	_apply_volumes()
	_apply_fullscreen()
	save_settings()


static func get_setting(key: String):
	if _cache.is_empty():
		load_settings()
	return _cache.get(key, DEFAULTS.get(key))


static func set_setting(key: String, value) -> void:
	if _cache.is_empty():
		load_settings()
	_cache[key] = value
	if key.ends_with("_volume"):
		_apply_volumes()
	elif key == "fullscreen":
		_apply_fullscreen()
	save_settings()


## Controller vibration master switch. Game code gates Input.start_joy_vibration
## on this (cutscene rumble steps call it when enabled).
static func vibration_enabled() -> bool:
	return bool(get_setting("vibration"))


static func _ensure_buses() -> void:
	if AudioServer.bus_count < 1:
		return
	for bus_name in ["Music", "SFX"]:
		if AudioServer.get_bus_index(bus_name) < 0:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, bus_name)


static func _bus_volume_db(bus_name: String, pct: int) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return
	var linear := clampf(float(pct) / 100.0, 0.0, 1.0)
	# 0% = silence (-80db); otherwise map to a usable db curve.
	var db := -80.0 if linear <= 0.001 else linear_to_db(linear)
	AudioServer.set_bus_volume_db(idx, db)


static func _apply_volumes() -> void:
	_bus_volume_db("Master", int(_cache.get("master_volume", 80)))
	_bus_volume_db("Music", int(_cache.get("music_volume", 80)))
	_bus_volume_db("SFX", int(_cache.get("sfx_volume", 80)))


static func _apply_fullscreen() -> void:
	if OS.has_feature("web"):
		return
	var fs := bool(_cache.get("fullscreen", true))
	# Headless/dummy display servers may not support this — guard it.
	if DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_mode(
		DisplayServer.WINDOW_MODE_FULLSCREEN if fs else DisplayServer.WINDOW_MODE_WINDOWED
	)


# --- Instance (the UI overlay) ---------------------------------------------

var _open := false
var _built := false
var _rows: Array = []  # [{id, kind, label, control}]
var _selected := 0
var _title_label = null

const BONE := Color(0.92, 0.90, 0.86)
const DIM := Color(0.45, 0.44, 0.42)
const GOLD := Color(0.95, 0.80, 0.45)


func _ready() -> void:
	if _built:
		return
	_built = true
	layer = 14
	add_to_group("settings")
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	load_settings()
	_build()


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.75)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	center.add_child(box)
	var title := Label.new()
	title.text = "SETTINGS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 48)
	title.add_theme_color_override("font_color", GOLD)
	box.add_child(title)
	_title_label = title

	_add_slider(box, "master_volume", "Master Volume")
	_add_slider(box, "music_volume", "Music Volume")
	_add_slider(box, "sfx_volume", "SFX Volume")
	if not OS.has_feature("web"):
		_add_toggle(box, "fullscreen", "Fullscreen")
	_add_toggle(box, "vibration", "Controller Vibration")
	_add_button(box, "reset", "RESET TO DEFAULTS")
	_add_button(box, "back", "BACK")
	_refresh()


func _row_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 26)
	l.add_theme_color_override("font_color", BONE)
	l.custom_minimum_size = Vector2(300, 40)
	return l


func _add_slider(box: VBoxContainer, id: String, text: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(row)
	row.add_child(_row_label(text))
	var slider := HSlider.new()
	slider.min_value = 0
	slider.max_value = 100
	slider.step = 1
	slider.value = float(get_setting(id))
	slider.custom_minimum_size = Vector2(320, 40)
	slider.focus_mode = Control.FOCUS_NONE
	slider.value_changed.connect(_on_slider_changed.bind(id))
	row.add_child(slider)
	var val := Label.new()
	val.add_theme_font_size_override("font_size", 26)
	val.add_theme_color_override("font_color", DIM)
	val.custom_minimum_size = Vector2(70, 40)
	row.add_child(val)
	_rows.append({"id": id, "kind": "slider", "slider": slider, "value_label": val})


func _add_toggle(box: VBoxContainer, id: String, text: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(row)
	row.add_child(_row_label(text))
	var b := Button.new()
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(140, 40)
	b.add_theme_font_size_override("font_size", 26)
	var bid: String = id
	b.pressed.connect(_on_toggle_pressed.bind(bid))
	row.add_child(b)
	_rows.append({"id": id, "kind": "toggle", "button": b})


func _add_button(box: VBoxContainer, id: String, text: String) -> void:
	var b := Button.new()
	b.text = text
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(420, 48)
	b.add_theme_font_size_override("font_size", 28)
	b.add_theme_color_override("font_color", BONE)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	var bid: String = id
	b.pressed.connect(_on_button_pressed.bind(bid))
	b.mouse_entered.connect(_on_row_hovered.bind(_rows.size()))
	box.add_child(b)
	_rows.append({"id": id, "kind": "button", "button": b})


func is_open() -> bool:
	return _open


func open() -> void:
	if _open:
		return
	_open = true
	_selected = 0
	_refresh()
	visible = true


func close() -> void:
	if not _open:
		return
	_open = false
	visible = false
	closed.emit()


func _refresh() -> void:
	for i in _rows.size():
		var row: Dictionary = _rows[i]
		var selected := i == _selected
		match str(row["kind"]):
			"slider":
				var s: HSlider = row["slider"]
				s.value = float(get_setting(str(row["id"])))
				(row["value_label"] as Label).text = "%d" % int(s.value)
				(row["value_label"] as Label).add_theme_color_override(
					"font_color", GOLD if selected else DIM)
			"toggle":
				var on := bool(get_setting(str(row["id"])))
				var b: Button = row["button"]
				b.text = "ON" if on else "OFF"
				b.add_theme_color_override("font_color", GOLD if selected else BONE)
			"button":
				var bb: Button = row["button"]
				bb.modulate = Color(1, 1, 1) if selected else Color(0.75, 0.75, 0.78)


func _on_slider_changed(value: float, id: String) -> void:
	set_setting(id, int(value))
	_refresh()


func _on_toggle_pressed(id: String) -> void:
	set_setting(id, not bool(get_setting(id)))
	_refresh()


func _on_button_pressed(id: String) -> void:
	match id:
		"reset":
			reset_defaults()
			_refresh()
		"back":
			close()


func _on_row_hovered(idx: int) -> void:
	if idx >= 0 and idx < _rows.size():
		_selected = idx
		_refresh()


func move_selection(dir: int) -> void:
	_selected = posmod(_selected + dir, _rows.size())
	_refresh()


func adjust_selected(dir: int) -> void:
	var row: Dictionary = _rows[_selected]
	match str(row["kind"]):
		"slider":
			var s: HSlider = row["slider"]
			s.value = clampf(s.value + dir * 5.0, 0.0, 100.0)
			# value_changed fires -> set_setting + _refresh


func activate_selected() -> void:
	var row: Dictionary = _rows[_selected]
	match str(row["kind"]):
		"toggle":
			_on_toggle_pressed(str(row["id"]))
		"button":
			_on_button_pressed(str(row["id"]))
		"slider":
			pass  # sliders adjust with left/right


func _input(event: InputEvent) -> void:
	if not _open:
		return
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_up"):
		move_selection(-1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_down"):
		move_selection(1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_left"):
		adjust_selected(-1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_right"):
		adjust_selected(1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		activate_selected()
		get_viewport().set_input_as_handled()
