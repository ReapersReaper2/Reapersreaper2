extends Area2D
## Creep Pod cluster: harmless collectible for Reaper's Reaper (H4).
##
## NOTE: intentionally no class_name (project convention).
## E to collect when the player is in range: adds a Creep Pod to the
## inventory, plays a pickup line, then the cluster is gone (one-shot
## via the creep_pod_<id> flag). Teaches "not everything is a fight".

## Collectible identifier, e.g. "h4_1". The GameState flag is "pod_" + pod_id.
@export var pod_id: String = "h4_1"

const POD_ITEM := "creep_pod"
const ContractsScript = preload("res://scripts/contracts.gd")

## Placeholder pickup line (story bot replaces with canon).
const PICKUP_LINE := "You gather the creep pods. Soft, harmless, faintly warm."

var game_state = null
var _player_in_range: bool = false
var _dialogue_open: bool = false


func _ready() -> void:
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	if not body_exited.is_connected(_on_body_exited):
		body_exited.connect(_on_body_exited)
	if game_state == null and is_inside_tree():
		game_state = get_node_or_null("/root/GameState")
	_apply_sprite()
	# Already collected: hide.
	if _flag("pod_" + pod_id):
		visible = false


## Swap the greybox polygon for the real Creep Pods sprite when available.
## Headless-safe: FileAccess + ImageTexture (same pattern as npc.gd).
func _apply_sprite() -> void:
	var path := "res://assets/creatures/creep_pods.png"
	if not FileAccess.file_exists(path):
		return
	var img := Image.load_from_file(path)
	if img == null or img.is_empty():
		return
	var tex := ImageTexture.create_from_image(img)
	var sprite := Sprite2D.new()
	sprite.name = "Art"
	sprite.texture = tex
	# 384px art → ~64px tall in-world (they're tiny by canon).
	var s := 64.0 / float(tex.get_height())
	sprite.scale = Vector2(s, s)
	sprite.position = Vector2(0, -32)
	add_child(sprite)
	var poly := get_node_or_null("Pods") as Polygon2D
	if poly != null:
		poly.visible = false


func _flag(flag: String) -> bool:
	if game_state != null and game_state.has_method("get_flag"):
		return bool(game_state.get_flag(flag))
	return false


func _set_flag(flag: String, value: bool = true) -> void:
	if game_state != null and game_state.has_method("set_flag"):
		game_state.set_flag(flag, value)


func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player") and visible:
		_player_in_range = true
		$Prompt.visible = true


func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		_player_in_range = false
		$Prompt.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if _dialogue_open or not _player_in_range or not visible:
		return
	if event.is_action_pressed("interact"):
		get_viewport().set_input_as_handled()
		_collect.call_deferred()


func _collect() -> void:
	if not visible:
		return
	visible = false
	$Prompt.visible = false
	_player_in_range = false
	_set_flag("pod_" + pod_id)
	if game_state != null and game_state.has_method("add_item"):
		game_state.add_item(POD_ITEM, 1)
		ContractsScript.record_collect(game_state, POD_ITEM)
	var box = get_tree().get_first_node_in_group("dialogue_box") if is_inside_tree() else null
	if box != null and box.has_method("start_dialogue"):
		_dialogue_open = true
		if box.has_signal("dialogue_finished"):
			box.dialogue_finished.connect(_on_dialogue_finished, CONNECT_ONE_SHOT)
		box.start_dialogue([{"type": "direction", "text": PICKUP_LINE}])
	print("[POD] collected ", pod_id)


func _on_dialogue_finished() -> void:
	_dialogue_open = false
