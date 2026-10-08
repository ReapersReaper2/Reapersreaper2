extends Control
## Reaper's Reaper — title screen (greybox, procedural only, no art assets).
##
## NOTE: intentionally no class_name (project convention — see save_system.gd).
## Builds its whole UI in _ready() so it stays testable headless.
##
## Flow:
##   NEW GAME -> GameState.new_game(), boots room_p1 fresh.
##   CONTINUE -> GameState.load_from_slot(slot), restores the saved room.
##   QUIT     -> exits (desktop only; hidden on web).
## Slot selector (1-3) with per-slot chapter/playtime summary.
## Keyboard: up/down select, left/right slot, Enter confirm. All items clickable.
## Emits navigate_to(path) instead of changing scenes when `scene_changer`
## is injected (headless tests); otherwise uses the scene tree.

signal navigate_to(path: String)

const ROOM_SCENES := {
	"p1": "res://scenes/room_p1.tscn",
	"p3": "res://scenes/room_p3.tscn",
	"c1": "res://scenes/room_c1.tscn",
}
const FALLBACK_SCENE := "res://scenes/room_p1.tscn"

var game_state = null  # GameState autoload or injected (headless tests)
var scene_changer = null  # callable(path) override for tests

var _slot: int = 1
var _items: Array = []          # [{id, button}]
var _selected: int = 0
var _slot_label: Label = null
var _slot_summary: Label = null
var _built: bool = false

const BONE := Color(0.92, 0.90, 0.86)
const DIM := Color(0.45, 0.44, 0.50)
const GHOST := Color(0.62, 0.58, 0.72)


func _ready() -> void:
	if _built:
		return
	_built = true
	if game_state == null:
		game_state = get_node_or_null("/root/GameState")
	if game_state != null and game_state.has_method("get_current_slot"):
		_slot = clampi(game_state.get_current_slot(), 1, 3)
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_background()
	_build_text()
	_build_slots()
	_build_menu()
	_refresh()


func _build_background() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.015, 0.015, 0.035)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	# Soul-light motes drifting upward.
	var motes := CPUParticles2D.new()
	motes.amount = 70
	motes.lifetime = 7.0
	motes.preprocess = 7.0
	motes.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	motes.emission_rect_extents = Vector2(640, 40)
	motes.position = Vector2(640, 700)
	motes.direction = Vector2(0, -1)
	motes.spread = 12.0
	motes.initial_velocity_min = 12.0
	motes.initial_velocity_max = 30.0
	motes.gravity = Vector2.ZERO
	motes.scale_amount_min = 1.5
	motes.scale_amount_max = 3.5
	motes.color = Color(0.75, 0.70, 0.95, 0.35)
	add_child(motes)
	# Vignette: radial darkening toward the edges.
	var grad := Gradient.new()
	grad.set_color(0, Color(0, 0, 0, 0))
	grad.set_color(1, Color(0, 0, 0, 0.75))
	var vg_tex := GradientTexture2D.new()
	vg_tex.gradient = grad
	vg_tex.fill = GradientTexture2D.FILL_RADIAL
	vg_tex.fill_from = Vector2(0.5, 0.5)
	vg_tex.fill_to = Vector2(1.0, 0.5)
	var vg := TextureRect.new()
	vg.texture = vg_tex
	vg.set_anchors_preset(Control.PRESET_FULL_RECT)
	vg.stretch_mode = TextureRect.STRETCH_SCALE
	vg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vg)


func _build_text() -> void:
	var title := Label.new()
	title.text = "REAPER'S REAPER"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 96)
	title.add_theme_color_override("font_color", BONE)
	title.set_anchors_preset(Control.PRESET_CENTER_TOP)
	title.position = Vector2(-640, 120)
	title.size = Vector2(1280, 130)
	add_child(title)
	var sub := Label.new()
	sub.text = "the underworld remembers"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 26)
	sub.add_theme_color_override("font_color", GHOST)
	sub.set_anchors_preset(Control.PRESET_CENTER_TOP)
	sub.position = Vector2(-640, 252)
	sub.size = Vector2(1280, 40)
	add_child(sub)


func _build_slots() -> void:
	_slot_label = Label.new()
	_slot_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_slot_label.add_theme_font_size_override("font_size", 30)
	_slot_label.add_theme_color_override("font_color", BONE)
	_slot_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_slot_label.position = Vector2(-640, 330)
	_slot_label.size = Vector2(1280, 44)
	_slot_label.mouse_filter = Control.MOUSE_FILTER_STOP
	_slot_label.gui_input.connect(_on_slot_clicked)
	add_child(_slot_label)
	_slot_summary = Label.new()
	_slot_summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_slot_summary.add_theme_font_size_override("font_size", 20)
	_slot_summary.add_theme_color_override("font_color", DIM)
	_slot_summary.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_slot_summary.position = Vector2(-640, 376)
	_slot_summary.size = Vector2(1280, 30)
	add_child(_slot_summary)


func _build_menu() -> void:
	var defs := [
		{"id": "new", "text": "NEW GAME"},
		{"id": "continue", "text": "CONTINUE"},
		{"id": "settings", "text": "SETTINGS"},
	]
	if not OS.has_feature("web"):
		defs.append({"id": "quit", "text": "QUIT"})
	var y := 440.0
	for d in defs:
		var b := Button.new()
		b.text = str(d["text"])
		b.flat = true
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 34)
		b.add_theme_color_override("font_color", BONE)
		b.add_theme_color_override("font_hover_color", Color.WHITE)
		b.add_theme_color_override("font_disabled_color", Color(0.25, 0.25, 0.28))
		b.set_anchors_preset(Control.PRESET_CENTER_TOP)
		b.position = Vector2(-640, y)
		b.size = Vector2(1280, 52)
		var item_id: String = str(d["id"])
		b.pressed.connect(_on_item_pressed.bind(item_id))
		b.mouse_entered.connect(_on_item_hovered.bind(item_id))
		add_child(b)
		_items.append({"id": item_id, "button": b})
		y += 62.0
	var hint := Label.new()
	hint.text = "up/down select · left/right slot · enter confirm"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 18)
	hint.add_theme_color_override("font_color", DIM)
	hint.set_anchors_preset(Control.PRESET_CENTER_TOP)
	hint.position = Vector2(-640, 656)
	hint.size = Vector2(1280, 28)
	add_child(hint)


func _refresh() -> void:
	_slot_label.text = "<  SLOT %d  >" % _slot
	_slot_summary.text = slot_summary(_slot)
	for i in _items.size():
		var item: Dictionary = _items[i]
		var b: Button = item["button"]
		var enabled := _item_enabled(str(item["id"]))
		b.disabled = not enabled
		var prefix := "> " if (i == _selected and enabled) else "   "
		b.text = prefix + _item_text(str(item["id"]))
		if i == _selected and enabled:
			b.modulate = Color(1, 1, 1)
		elif not enabled:
			b.modulate = Color(1, 1, 1, 0.35)
		else:
			b.modulate = Color(0.8, 0.8, 0.82)


func _item_text(item_id: String) -> String:
	for item in _items:
		if str(item["id"]) == item_id:
			return (item["button"] as Button).text.trim_prefix("> ").trim_prefix("   ")
	return item_id.to_upper()


func _item_enabled(item_id: String) -> bool:
	if item_id == "continue":
		return game_state != null and game_state.has_method("has_save") and game_state.has_save(_slot)
	return true


func slot_summary(slot: int) -> String:
	if game_state == null or not game_state.has_method("has_save") or not game_state.has_save(slot):
		return "— empty —"
	var ss = game_state.save_system
	if ss == null or not ss.has_method("get_save_info"):
		return "— saved —"
	var info: Dictionary = ss.get_save_info(slot)
	var chapter: String = str(info.get("chapter", "")).capitalize()
	if chapter.is_empty():
		chapter = "Unknown"
	return "%s · %s" % [chapter, format_playtime(float(info.get("playtime", 0.0)))]


static func format_playtime(seconds: float) -> String:
	var total := int(seconds)
	var h := total / 3600
	var m := (total % 3600) / 60
	var s := total % 60
	return "%d:%02d:%02d" % [h, m, s]


func _on_slot_clicked(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			cycle_slot(1)


func cycle_slot(dir: int) -> void:
	_slot = 1 + posmod(_slot - 1 + dir, 3)
	if game_state != null and game_state.has_method("set_current_slot"):
		game_state.set_current_slot(_slot)
	_refresh()


func move_selection(dir: int) -> void:
	# Skip disabled items; wrap around.
	var n := _items.size()
	if n == 0:
		return
	for _k in n:
		_selected = posmod(_selected + dir, n)
		if _item_enabled(str(_items[_selected]["id"])):
			break
	_refresh()


func activate_selected() -> void:
	var item_id: String = str(_items[_selected]["id"])
	activate(item_id)


func activate(item_id: String) -> void:
	if not _item_enabled(item_id):
		return
	match item_id:
		"new":
			_new_game()
		"continue":
			_continue()
		"settings":
			_open_settings()
		"quit":
			get_tree().quit()


func _new_game() -> void:
	if game_state != null and game_state.has_method("new_game"):
		game_state.new_game()
		if game_state.has_method("set_current_slot"):
			game_state.set_current_slot(_slot)
	_goto(FALLBACK_SCENE)


func _continue() -> void:
	var path := FALLBACK_SCENE
	if game_state != null and game_state.has_method("load_from_slot"):
		if game_state.load_from_slot(_slot):
			var pos: Dictionary = game_state.get_position()
			path = str(ROOM_SCENES.get(str(pos.get("room", "p1")), FALLBACK_SCENE))
	_goto(path)


func _open_settings() -> void:
	var existing = get_tree().get_first_node_in_group("settings")
	if existing != null and existing.has_method("open"):
		existing.open()
		return
	var SettingsScript = load("res://scripts/settings.gd")
	var panel = SettingsScript.new()
	get_tree().root.add_child(panel)
	panel._ready()
	panel.open()


func _goto(path: String) -> void:
	if scene_changer != null and scene_changer.is_valid():
		scene_changer.call(path)
		return
	get_tree().change_scene_to_file(path)


func _on_item_pressed(item_id: String) -> void:
	for i in _items.size():
		if str(_items[i]["id"]) == item_id:
			_selected = i
			break
	activate(item_id)


func _on_item_hovered(item_id: String) -> void:
	for i in _items.size():
		if str(_items[i]["id"]) == item_id and _item_enabled(item_id):
			_selected = i
			_refresh()
			break


func _input(event: InputEvent) -> void:
	# The settings panel owns input while it's open.
	var sp = get_tree().get_first_node_in_group("settings")
	if sp != null and sp.has_method("is_open") and sp.is_open():
		return
	if event.is_action_pressed("ui_up"):
		move_selection(-1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_down"):
		move_selection(1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_left"):
		cycle_slot(-1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_right"):
		cycle_slot(1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		activate_selected()
		get_viewport().set_input_as_handled()
