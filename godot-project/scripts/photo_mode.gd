extends CanvasLayer
## Reaper's Reaper — Photo Mode.
##
## NOTE: intentionally no class_name (project convention — see save_system.gd).
## Instanced by room.gd on P key (or from pause menu). Freezes the game,
## gives free camera controls, filters, and creature poses. Screenshot
## capture saves to user://screenshots/. The Steam share button is stubbed
## for M5 (logs until the Steamworks SDK lands).
##
## Controls:
##   WASD/arrows: pan camera
##   Q/E or wheel: zoom
##   F: cycle filter
##   C: cycle creature pose
##   S: take screenshot
##   H: share to Steam (stub)
##   P/Esc: exit photo mode

signal exited

var game_state = null  # GameState autoload or injected (headless tests)

var _active: bool = false
var _camera_offset: Vector2 = Vector2.ZERO
var _zoom: float = 1.0
var _filter_idx: int = 0
var _pose_idx: int = 0
var _built: bool = false
var _filter_rect: ColorRect = null
var _hint_label: Label = null

const SCREENSHOT_DIR := "user://screenshots"

## Filters: name -> tint color (applied as a full-screen overlay).
const FILTERS: Array = [
	{"name": "None", "color": Color(0, 0, 0, 0)},
	{"name": "Noir", "color": Color(0.1, 0.1, 0.15, 0.35)},
	{"name": "Ember", "color": Color(0.4, 0.15, 0.05, 0.25)},
	{"name": "Gravebloom", "color": Color(0.15, 0.3, 0.1, 0.25)},
	{"name": "Soul Light", "color": Color(0.2, 0.2, 0.4, 0.2)},
]

## Creature poses for the party lead (cycles through available animations).
const POSES: Array = ["idle", "attack", "hurt", "victory"]


func _ready() -> void:
	if game_state == null:
		game_state = get_node_or_null("/root/GameState")
	layer = 200
	visible = false


func is_active() -> bool:
	return _active


func activate() -> void:
	if _active:
		return
	_active = true
	if not _built:
		_build()
	visible = true
	get_tree().paused = true
	_update_hint()


func deactivate() -> void:
	if not _active:
		return
	_active = false
	visible = false
	get_tree().paused = false
	exited.emit()


func _build() -> void:
	_built = true
	_filter_rect = ColorRect.new()
	_filter_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_filter_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_filter_rect)
	_hint_label = Label.new()
	_hint_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.add_theme_font_size_override("font_size", 18)
	add_child(_hint_label)


func _update_hint() -> void:
	if _hint_label == null:
		return
	var f: Dictionary = FILTERS[_filter_idx]
	_hint_label.text = "WASD pan | Q/E zoom | F filter: %s | C pose: %s | S screenshot | H share | P exit" % [str(f["name"]), POSES[_pose_idx]]


func cycle_filter() -> void:
	_filter_idx = (_filter_idx + 1) % FILTERS.size()
	_apply_filter()
	_update_hint()


func _apply_filter() -> void:
	if _filter_rect == null:
		return
	_filter_rect.color = FILTERS[_filter_idx]["color"]


func cycle_pose() -> void:
	_pose_idx = (_pose_idx + 1) % POSES.size()
	# Pose the party lead's visual if one is available.
	var party_visual = get_tree().get_nodes_in_group("party_visual")
	if not party_visual.is_empty():
		var v = party_visual[0]
		if v.has_method("play_pose"):
			v.play_pose(POSES[_pose_idx])
	_update_hint()


func take_screenshot() -> String:
	DirAccess.make_dir_recursive_absolute(SCREENSHOT_DIR)
	var img := get_viewport().get_texture().get_image()
	var path := "%s/photo_%d.png" % [SCREENSHOT_DIR, Time.get_unix_time_from_system()]
	img.save_png(path)
	return path


## Steam share (M5): posts the screenshot to Steam with the game's tags.
## Stub: logs until the Steamworks SDK lands.
func share_to_steam(screenshot_path: String) -> bool:
	# M5: call Steam.screenshot / Steamworks share API here.
	print("[PHOTO] share_to_steam stub (M5): ", screenshot_path)
	return false


func _unhandled_input(event: InputEvent) -> void:
	if not _active:
		return
	if event.is_action_pressed("photo_exit") or event.is_action_pressed("ui_cancel"):
		deactivate()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("photo_filter"):
		cycle_filter()
	elif event.is_action_pressed("photo_pose"):
		cycle_pose()
	elif event.is_action_pressed("photo_capture"):
		var path := take_screenshot()
		print("[PHOTO] screenshot saved: ", path)
	elif event.is_action_pressed("photo_share"):
		var path := take_screenshot()
		share_to_steam(path)
