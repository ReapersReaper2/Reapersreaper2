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

func _ready() -> void:
	if not DisplayServer.is_touchscreen_available():
		visible = false
		return
	overlay = MobileOverlay.new()
	overlay.name = "MobileHUD"
	overlay.joystick_radius = joystick_radius
	overlay.action_radius = action_button_radius
	overlay.edge_margin = edge_margin
	add_child(overlay)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
