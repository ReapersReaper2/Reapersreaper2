extends CanvasLayer
## Reaper's Reaper — projection picker overlay.
##
## NOTE: intentionally no class_name (project convention). Code-built UI
## (twitch_vote_ui.gd pattern). Lists the memories Mollosar still holds;
## picking one burns it and starts a projection (Memories.project).
##
## Usage (room.gd):
##   var ui: CanvasLayer = MemoriesUIScript.new()
##   ui.pick(game_state)            # shows; emits memory_picked(key)
##   ui.hide_ui()
## Cancel: Esc or the Cancel row -> emits memory_picked("").

signal memory_picked(key: String)

const MemoriesScript := preload("res://scripts/memories.gd")

var _built: bool = false
var _panel: PanelContainer = null
var _title: Label = null
var _vb: VBoxContainer = null


func _ready() -> void:
	layer = 220
	visible = false


func _ensure_built() -> void:
	if _built:
		return
	_built = true
	_panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.03, 0.02, 0.06, 0.92)
	style.set_corner_radius_all(10)
	style.set_border_width_all(1)
	style.border_color = Color(0.55, 0.45, 0.8, 0.7)
	style.content_margin_left = 20
	style.content_margin_right = 20
	style.content_margin_top = 16
	style.content_margin_bottom = 16
	_panel.add_theme_stylebox_override("panel", style)
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.custom_minimum_size = Vector2(460, 0)
	add_child(_panel)
	_vb = VBoxContainer.new()
	_vb.add_theme_constant_override("separation", 8)
	_panel.add_child(_vb)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 22)
	_title.add_theme_color_override("font_color", Color(0.85, 0.78, 1.0))
	_vb.add_child(_title)


func _clear_rows() -> void:
	for c in _vb.get_children():
		if c != _title:
			c.queue_free()


func _add_option(label: String, key: String, dim: bool = false) -> void:
	var b := Button.new()
	b.text = label
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(420, 34)
	b.add_theme_font_size_override("font_size", 19)
	b.add_theme_color_override("font_color", Color(0.6, 0.58, 0.7) if dim else Color(0.92, 0.9, 0.96))
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.pressed.connect(func() -> void: _choose(key))
	_vb.add_child(b)


func _choose(key: String) -> void:
	hide_ui()
	memory_picked.emit(key)


## Show the picker. Emits memory_picked(key) on selection, memory_picked("")
## on cancel (Esc handled by the caller via hide_ui + emit).
func pick(gs) -> void:
	_ensure_built()
	_clear_rows()
	_title.text = "Project a memory — it will be gone."
	var owned: Array = MemoriesScript.owned(gs)
	for key in owned:
		_add_option("%s — %s" % [MemoriesScript.memory_name(key), MemoriesScript.memory_desc(key)], key)
	_add_option("[ Let it go — cancel ]", "", true)
	visible = true


func hide_ui() -> void:
	visible = false
