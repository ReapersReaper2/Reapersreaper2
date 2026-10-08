extends CanvasLayer
## Reaper's Reaper — pause menu overlay.
##
## NOTE: intentionally no class_name (project convention — see save_system.gd).
## Instanced by room.gd on ui_cancel. Dims the game, pauses the tree, and
## offers RESUME / SAVE / QUIT TO TITLE. Keyboard: up/down + Enter; clickable.
## Esc while open resumes (handled here so the room doesn't double-toggle).

signal closed

var game_state = null  # GameState autoload or injected (headless tests)
var scene_changer = null  # callable(path) override for tests

var _items: Array = []  # [{id, button}]
var _selected: int = 0
var _open: bool = false
var _save_flash: float = 0.0
var _save_button: Button = null
var _built: bool = false

const BONE := Color(0.92, 0.90, 0.86)

const PartyPanelScript := preload("res://scripts/party_panel.gd")
const BreedingUIScript := preload("res://scripts/breeding_ui.gd")
const SettingsScript := preload("res://scripts/settings.gd")
const JournalScript := preload("res://scripts/journal.gd")


func _ready() -> void:
	if _built:
		return
	_built = true
	layer = 10
	if game_state == null:
		game_state = get_node_or_null("/root/GameState")
	add_to_group("pause_menu")
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build()


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.65)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	center.add_child(box)
	var title := Label.new()
	title.text = "PAUSED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 48)
	title.add_theme_color_override("font_color", BONE)
	box.add_child(title)
	for d in [
		{"id": "resume", "text": "RESUME"},
		{"id": "party", "text": "PARTY"},
		{"id": "breeding", "text": "BREEDING"},
		{"id": "journal", "text": "JOURNAL"},
		{"id": "save", "text": "SAVE"},
		{"id": "settings", "text": "SETTINGS"},
		{"id": "title", "text": "QUIT TO TITLE"},
	]:
		var b := Button.new()
		b.text = str(d["text"])
		b.flat = true
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(420, 48)
		b.add_theme_font_size_override("font_size", 30)
		b.add_theme_color_override("font_color", BONE)
		b.add_theme_color_override("font_hover_color", Color.WHITE)
		var item_id: String = str(d["id"])
		b.pressed.connect(_on_pressed.bind(item_id))
		b.mouse_entered.connect(_on_hovered.bind(item_id))
		box.add_child(b)
		_items.append({"id": item_id, "button": b})
		if item_id == "save":
			_save_button = b


func is_open() -> bool:
	return _open


func open() -> void:
	if _open:
		return
	_open = true
	_selected = 0
	_refresh()
	visible = true
	get_tree().paused = true


func close() -> void:
	if not _open:
		return
	_open = false
	visible = false
	get_tree().paused = false
	closed.emit()


func _refresh() -> void:
	for i in _items.size():
		var b: Button = _items[i]["button"]
		var prefix := "> " if i == _selected else "   "
		var base := _item_text(str(_items[i]["id"]))
		if str(_items[i]["id"]) == "save" and _save_flash > 0.0:
			base = "SAVED ✓"
		b.text = prefix + base
		b.modulate = Color(1, 1, 1) if i == _selected else Color(0.75, 0.75, 0.78)


func _item_text(item_id: String) -> String:
	match item_id:
		"resume":
			return "RESUME"
		"party":
			return "PARTY"
		"breeding":
			return "BREEDING"
		"journal":
			return "JOURNAL"
		"save":
			return "SAVE"
		"settings":
			return "SETTINGS"
		"title":
			return "QUIT TO TITLE"
	return item_id.to_upper()


func move_selection(dir: int) -> void:
	_selected = posmod(_selected + dir, _items.size())
	_refresh()


func activate(item_id: String) -> void:
	match item_id:
		"resume":
			close()
		"party":
			_open_party_panel()
		"breeding":
			_open_breeding_panel()
		"journal":
			_open_journal()
		"save":
			_do_save()
		"settings":
			_open_settings()
		"title":
			_quit_to_title()


## Open the party panel over the pause menu. The menu stays open (and the
## tree stays paused); closing the panel returns here.
func _open_party_panel() -> void:
	if get_tree().get_first_node_in_group("party_panel") != null:
		return
	var panel = PartyPanelScript.new()
	panel.game_state = game_state
	get_tree().root.add_child(panel)
	panel._ready()
	panel.open()


## Open the breeding & nursery panel over the pause menu. Same pattern:
## the menu stays open (and the tree stays paused); closing returns here.
func _open_breeding_panel() -> void:
	if get_tree().get_first_node_in_group("breeding_ui") != null:
		return
	var panel = BreedingUIScript.new()
	panel.game_state = game_state
	get_tree().root.add_child(panel)
	panel._ready()
	panel.open()


## Open the journal over the pause menu. Same pattern: the menu stays open
## (and the tree stays paused); closing the journal returns here.
func _open_journal() -> void:
	var existing = get_tree().get_first_node_in_group("journal")
	if existing != null and existing.has_method("is_open") and not existing.is_open():
		existing.open()
		return
	if existing != null:
		return
	var panel = JournalScript.new()
	panel.game_state = game_state
	get_tree().root.add_child(panel)
	panel._ready()
	panel.open()


## Open the settings panel over the pause menu. The menu stays open (and the
## tree stays paused); closing settings returns here.
func _open_settings() -> void:
	var existing = get_tree().get_first_node_in_group("settings")
	if existing != null and existing.has_method("is_open") and not existing.is_open():
		existing.open()
		return
	if existing != null:
		return
	var panel = SettingsScript.new()
	get_tree().root.add_child(panel)
	panel._ready()
	panel.open()


func _do_save() -> void:
	if game_state != null and game_state.has_method("save_to_slot") and game_state.has_method("get_current_slot"):
		game_state.save_to_slot(game_state.get_current_slot())
	_save_flash = 1.2
	_refresh()


func _quit_to_title() -> void:
	var path := "res://scenes/title_screen.tscn"
	get_tree().paused = false
	_open = false
	if scene_changer != null and scene_changer.is_valid():
		scene_changer.call(path)
		return
	get_tree().change_scene_to_file(path)


func _on_pressed(item_id: String) -> void:
	for i in _items.size():
		if str(_items[i]["id"]) == item_id:
			_selected = i
			break
	activate(item_id)


func _on_hovered(item_id: String) -> void:
	for i in _items.size():
		if str(_items[i]["id"]) == item_id:
			_selected = i
			_refresh()
			break


func _process(delta: float) -> void:
	if _save_flash > 0.0:
		_save_flash -= delta
		if _save_flash <= 0.0:
			_refresh()


func _input(event: InputEvent) -> void:
	if not _open:
		return
	# The party panel and settings own input while they're open (they close
	# back to us).
	if get_tree().get_first_node_in_group("party_panel") != null:
		return
	var sp = get_tree().get_first_node_in_group("settings")
	if sp != null and sp.has_method("is_open") and sp.is_open():
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
	elif event.is_action_pressed("ui_accept"):
		activate(str(_items[_selected]["id"]))
		get_viewport().set_input_as_handled()
