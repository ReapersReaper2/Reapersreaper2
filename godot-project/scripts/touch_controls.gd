extends CanvasLayer
class_name TouchControls
## Responsive multitouch mobile controls for Reaper's Reaper.
## The screen-space child draws the joystick/buttons and feeds existing
## InputMap actions; keyboard/gamepad input and player movement stay intact.

const MobileOverlay := preload("res://scripts/mobile_touch_overlay.gd")

@export var joystick_radius: float = 82.0
@export var action_button_radius: float = 53.0
@export var edge_margin: float = 40.0

var overlay: Control = null

## Seamless battles display their own combat UI. Hiding this CanvasLayer
## alone is not enough: MobileHUD handles touches through Node._input, which
## can still consume events from behind the battle screen.
var _battle_suspended: bool = false
var _battle_was_visible: bool = false
var _battle_was_processing_input: bool = false


func suspend_for_battle() -> void:
	if _battle_suspended:
		return
	_battle_suspended = true
	_battle_was_visible = visible
	if overlay != null and is_instance_valid(overlay):
		_battle_was_processing_input = overlay.is_processing_input()
		if overlay.has_method("_cancel_gameplay_touches"):
			overlay._cancel_gameplay_touches()
		# Paused/menu fingers belong to the old overworld input state too.
		overlay.set("_pause_id", -1)
		overlay.set_process_input(false)
	visible = false


func resume_after_battle() -> void:
	if not _battle_suspended:
		return
	_battle_suspended = false
	if overlay != null and is_instance_valid(overlay):
		overlay.set_process_input(_battle_was_processing_input)
	visible = _battle_was_visible


func _ready() -> void:
	if not DisplayServer.is_touchscreen_available():
		visible = false
		return
	overlay = MobileOverlay.new()
	overlay.name = "MobileHUD"
	overlay.set("joystick_radius", joystick_radius)
	overlay.set("action_radius", action_button_radius)
	overlay.set("edge_margin", edge_margin)
	add_child(overlay)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
