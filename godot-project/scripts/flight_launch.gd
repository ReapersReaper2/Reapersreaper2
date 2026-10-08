extends Node2D
## FlightLaunch — U4 "first flight" beat controller.
##
## Connects to the LaunchPoint lore object's `activated` signal. When the
## player takes the launch prompt:
## - If flight is available: the player takes off immediately (the
##   tutorial beat — "falling is just flying with commitment").
## - If not: the locked hint is shown (wings not yet earned, or depowered).
##
## Follows the boss-controller pattern (Node2D, activated signal).
## NOTE: intentionally no class_name (project convention).

const Flight := preload("res://scripts/flight.gd")

## Name of the LaunchPoint lore object node in the room.
@export var launch_point_name: String = "LaunchPoint"

var _launch = null
var _player = null


func _ready() -> void:
	_launch = get_parent().get_node_or_null(launch_point_name) if get_parent() != null else null
	_player = get_parent().get_node_or_null("Player") if get_parent() != null else null
	if _launch != null and _launch.has_signal("activated"):
		if not _launch.activated.is_connected(_on_launch_activated):
			_launch.activated.connect(_on_launch_activated)


func _on_launch_activated(_obj) -> void:
	if _player == null or not is_instance_valid(_player):
		return
	if not _player.has_method("take_off"):
		return
	var gs = get_node_or_null("/root/GameState")
	if Flight.can_fly(gs):
		_player.take_off()
		print("[FLIGHT] U4 launch: first flight")
	else:
		_say_hint(Flight.locked_hint(gs))


func _say_hint(text: String) -> void:
	if text == "":
		return
	var box = get_tree().get_first_node_in_group("dialogue_box") if is_inside_tree() else null
	if box != null and box.has_method("start_dialogue"):
		box.start_dialogue([{"type": "direction", "text": text}])
	else:
		print("[FLIGHT] ", text)
