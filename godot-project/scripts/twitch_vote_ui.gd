extends CanvasLayer
## Reaper's Reaper — Twitch vote overlay.
##
## NOTE: intentionally no class_name (project convention — see save_system.gd).
## Code-built UI (photo_mode.gd pattern). Shows the active viewer vote:
## title, one row per option with live vote counts, a countdown bar, and a
## result banner when the vote closes. Driven by game code reading
## Twitch.get_vote_state() each frame while a vote is open.
##
## Usage (room.gd / wild_zone.gd):
##   var ui: CanvasLayer = TwitchVoteUIScript.new()
##   ui.show_vote(Twitch.get_vote_state())
##   # each frame: ui.refresh(Twitch.get_vote_state())
##   ui.show_result("Rare Sighting")
##   ui.hide_ui()

var _built: bool = false
var _panel: PanelContainer = null
var _title: Label = null
var _rows: Array = []        # option row Labels, parallel to state options
var _countdown: ProgressBar = null
var _count_label: Label = null
var _result: Label = null


func _ready() -> void:
	layer = 210
	visible = false


func _ensure_built() -> void:
	if _built:
		return
	_built = true
	_panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.02, 0.05, 0.88)
	style.set_corner_radius_all(10)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	_panel.add_theme_stylebox_override("panel", style)
	_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_panel.position = Vector2(-360, 16)
	_panel.custom_minimum_size = Vector2(330, 0)
	add_child(_panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	_panel.add_child(vb)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 20)
	_title.add_theme_color_override("font_color", Color(0.75, 0.6, 1.0))
	vb.add_child(_title)
	_countdown = ProgressBar.new()
	_countdown.min_value = 0
	_countdown.max_value = 1
	_countdown.custom_minimum_size = Vector2(0, 10)
	_countdown.show_percentage = false
	vb.add_child(_countdown)
	_count_label = Label.new()
	_count_label.add_theme_font_size_override("font_size", 13)
	_count_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75))
	vb.add_child(_count_label)
	_result = Label.new()
	_result.add_theme_font_size_override("font_size", 18)
	_result.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	_result.visible = false
	vb.add_child(_result)
	# Keep a handle to the VBox for option rows.
	_panel.set_meta("vbox", vb)


## Show a fresh vote. state comes from Twitch.get_vote_state().
func show_vote(state: Dictionary) -> void:
	_ensure_built()
	_clear_rows()
	var kind: String = str(state.get("kind", ""))
	_title.text = "Viewers vote: " + ("BLESSING" if kind == "blessing" else "TRIAL")
	_result.visible = false
	var vb: VBoxContainer = _panel.get_meta("vbox")
	_rows.clear()
	var opts: Array = state.get("options", [])
	for i in opts.size():
		var o: Dictionary = opts[i]
		var row := Label.new()
		row.add_theme_font_size_override("font_size", 15)
		row.add_theme_color_override("font_color", Color(0.92, 0.92, 0.95))
		row.text = _row_text(i, o)
		vb.add_child(row)
		_rows.append(row)
	visible = true
	refresh(state)


func _row_text(i: int, o: Dictionary) -> String:
	return "%d. %s — %s  (%d)" % [i + 1, str(o.get("name", "")), str(o.get("desc", "")), int(o.get("votes", 0))]


func _clear_rows() -> void:
	for r in _rows:
		if is_instance_valid(r):
			r.queue_free()
	_rows.clear()


## Update counts + countdown from a fresh Twitch.get_vote_state().
func refresh(state: Dictionary) -> void:
	if not _built or state.is_empty():
		return
	_result.visible = false
	var opts: Array = state.get("options", [])
	for i in mini(_rows.size(), opts.size()):
		(_rows[i] as Label).text = _row_text(i, opts[i])
	var left: float = float(state.get("seconds_left", 0.0))
	_countdown.value = clampf(left / 60.0, 0.0, 1.0)
	_count_label.text = "%d votes · %ds left · chat: !vote <number>" % [int(state.get("total_votes", 0)), int(ceili(left))]


## Show the winning option as a result banner. Call hide_ui() when done.
func show_result(winner_name: String) -> void:
	_ensure_built()
	_result.text = "Viewers chose: " + winner_name
	_result.visible = true
	visible = true


func hide_ui() -> void:
	visible = false
	if _built:
		_result.visible = false
