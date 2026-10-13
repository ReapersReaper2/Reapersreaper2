extends Node2D
## Presentation-only world Y depth matching the painted garden trees.

@export var player_foot_offset: float = 64.0
@export var luna_contact_offset: float = 12.0
var _player: Node2D
var _luna: Node2D
var _creatures: Node2D
var _ivy: Node2D

static func layer_for_ground_y(y: float) -> int:
	return clampi(int(roundf(y)), -1890, 1890)

func _ready() -> void:
	_refresh_targets()
	apply_depths()

func _refresh_targets() -> void:
	var room := get_parent()
	if room == null:
		return
	_player = room.get_node_or_null("Player")
	_luna = room.get_node_or_null("Luna")
	_creatures = room.get_node_or_null("Creatures")
	_ivy = room.get_node_or_null("Ivy")

func _process(_delta: float) -> void:
	apply_depths()

func apply_depths() -> void:
	if _player == null or not is_instance_valid(_player):
		_refresh_targets()
	if _player != null and is_instance_valid(_player):
		_set_layer(_player, _player.position.y + player_foot_offset)
	if _luna != null and is_instance_valid(_luna):
		_set_layer(_luna, _luna.position.y + luna_contact_offset)
	if _ivy != null and is_instance_valid(_ivy):
		_set_layer(_ivy, _ivy.position.y)
	if _creatures == null or not is_instance_valid(_creatures):
		return
	for resident in _creatures.get_children():
		if not (resident is Node2D) or not (resident is CanvasItem):
			continue
		var ground_y: float = (resident as Node2D).position.y
		if resident.has_method("depth_ground_y"):
			ground_y = float(resident.call("depth_ground_y"))
		_set_layer(resident, ground_y)
		var prompt = _creatures.get_node_or_null(String(resident.name) + "_InteractPrompt")
		if prompt is CanvasItem:
			_set_layer(prompt, ground_y + 1.0)

func _set_layer(actor: CanvasItem, ground_y: float) -> void:
	var desired := layer_for_ground_y(ground_y)
	actor.z_as_relative = false
	if actor.z_index != desired:
		actor.z_index = desired
