extends Area2D
## Tendril — climbable plant tendril (M3 traversal mechanic).
##
## Player grabs with [E]; the tendril carries them along `waypoints`
## (global positions) to the destination, then releases. The ride is
## repeatable. Gated on Depower.plant_abilities_available: FULL depower
## blocks the grab (the plant arm is dead); PARTIAL and NONE allow it.
##
## NOTE: intentionally no class_name (project convention).
## Standard children expected: "Range" (CollisionShape2D), "Prompt" (Label),
## "Visual" (Polygon2D, optional — tinted by `tint` if present).
##
## Design note: the M3 layout doc calls for "anchor points, swing physics"
## (grapple-equivalent). This implements the ride-along-path first pass
## ("test the feel before locking") — swing physics can layer on later.

const Depower := preload("res://scripts/depower.gd")

## Emitted when a ride starts / finishes.
signal ride_started(tendril)
signal ride_finished(tendril)

@export var prompt_text: String = "[E] grab tendril"
@export var label_text: String = "Tendril"
@export var tint: Color = Color(0.35, 0.50, 0.30)
## Ride path in GLOBAL coordinates. First point should be at/near the
## tendril's grab position; last point is the release destination.
@export var waypoints: PackedVector2Array = PackedVector2Array()
@export var ride_speed: float = 420.0
## Primary flag set when a ride completes (tracking, not one-shot).
@export var flag: String = ""
## Shown (via dialogue box) when the depower gate blocks the grab.
@export var locked_hint: String = "The tendril doesn't answer. Your plant arm is dead."

var _player_in_range := false
var _player_body = null
var _riding := false
var _rider = null
var _seg := 0


func _ready() -> void:
	if has_node("Visual"):
		($Visual as Polygon2D).color = tint
	if has_node("Prompt"):
		($Prompt as Label).text = prompt_text
		($Prompt as Label).visible = false
	if not is_inside_tree():
		return  # headless -s: tree services unavailable until inside tree
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	if not body_exited.is_connected(_on_body_exited):
		body_exited.connect(_on_body_exited)


func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	_player_in_range = true
	_player_body = body
	if has_node("Prompt"):
		($Prompt as Label).visible = true


func _on_body_exited(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	_player_in_range = false
	_player_body = null
	if has_node("Prompt"):
		($Prompt as Label).visible = false


func _unhandled_input(event: InputEvent) -> void:
	if _riding or not _player_in_range or _player_body == null:
		return
	if event.is_action_pressed("interact"):
		get_viewport().set_input_as_handled()
		var gs = get_node_or_null("/root/GameState")
		if not can_grab(gs):
			_say(locked_hint)
			return
		start_ride(_player_body, gs)


func _physics_process(delta: float) -> void:
	if _riding:
		if tick_ride(delta):
			_finish_ride()


## --- Public API (also used headless by tendril_test.gd) -----------------

## Whether the grab is allowed right now (depower gate).
func can_grab(gs) -> bool:
	if gs == null:
		return true  # headless / no state: allow
	return Depower.plant_abilities_available(gs)


## Begin the ride. Returns false if it can't start.
func start_ride(player, gs) -> bool:
	if _riding:
		return false
	if player == null or not is_instance_valid(player):
		return false
	if waypoints.size() < 2:
		push_warning("tendril.gd: need at least 2 waypoints to ride")
		return false
	if not can_grab(gs):
		return false
	_riding = true
	_rider = player
	_seg = 0
	_set_rider_locks(player, true)
	# Snap to the path start so the ride begins cleanly.
	player.global_position = waypoints[0]
	ride_started.emit(self)
	return true


## Advance the ride by delta. Returns true when the ride is complete.
func tick_ride(delta: float) -> bool:
	if not _riding or _rider == null or not is_instance_valid(_rider):
		return true
	var target: Vector2 = waypoints[_seg + 1]
	var pos: Vector2 = _rider.global_position
	var step: float = ride_speed * delta
	if pos.distance_to(target) <= step:
		_rider.global_position = target
		_seg += 1
		return _seg >= waypoints.size() - 1
	_rider.global_position = pos.move_toward(target, step)
	return false


func is_riding() -> bool:
	return _riding


## --- Internals ----------------------------------------------------------

func _finish_ride() -> void:
	_riding = false
	if _rider != null and is_instance_valid(_rider):
		_set_rider_locks(_rider, false)
	_rider = null
	_seg = 0
	var gs = get_node_or_null("/root/GameState")
	if gs != null and flag != "" and gs.has_method("set_flag"):
		gs.set_flag(flag, true)
	ride_finished.emit(self)


func _set_rider_locks(player, locked: bool) -> void:
	# The rider is ReaperPlayer (or a test mock with the same vars).
	player.move_locked = locked
	player.input_locked = locked
	player.tendril_riding = locked


func _say(text: String) -> void:
	if not is_inside_tree():
		print("[TENDRIL] ", text)
		return
	var box = get_tree().get_first_node_in_group("dialogue_box")
	if box != null and box.has_method("start_dialogue"):
		box.start_dialogue([{"type": "direction", "text": text}])
	else:
		print("[TENDRIL] ", text)
