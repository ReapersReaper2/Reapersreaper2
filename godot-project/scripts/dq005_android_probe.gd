extends Node2D
## DQ-005 diagnostic only: run the real opening bridge scene through the live player path.
const Room := preload("res://scenes/room_p1.tscn")
const Clips := preload("res://scripts/form1_attack_clips.gd")
const CELL := 384

func _ready() -> void:
	ProjectSettings.set_setting("debug/dq005_trace", true)
	call_deferred("_probe")

func _probe() -> void:
	print("[DQ005 ANDROID BRIDGE] begin")
	var bridge := Room.instantiate()
	add_child(bridge)
	var player: Node = bridge.get_node_or_null("Player")
	if player == null:
		printerr("[DQ005 ANDROID BRIDGE] FAIL no Player in room_p1")
		get_tree().quit(1)
		return
	player.set_physics_process(false)
	var rig: Node = player.get_node("ScytheRig")
	rig.set_physics_process(false)
	var manager = player.get("sprites")
	print("[DQ005 ANDROID BRIDGE] loaded_clips=%d has_sprites=%s form=%d" % [manager._attack_clips.size(), str(manager.has_sprites()), manager.current_form()])
	if manager._attack_clips.size() != 20:
		printerr("[DQ005 ANDROID BRIDGE] FAIL clips incomplete in actual bridge scene")
		get_tree().quit(1)
		return
	var passed := 0
	for direction in [Vector2.DOWN, Vector2.UP, Vector2.LEFT, Vector2.RIGHT]:
		player.set("facing", direction)
		for action_index in [1, 2, 3, 4, 5]:
			_prepare_action(player, rig, action_index)
			player.call("_physics_process", 0.0)
			var art: Sprite2D = manager._sprite
			var expected: Dictionary = Clips.sample(manager._attack_clips, action_index, 0.5, direction)
			var expected_texture: Texture2D = expected.get("texture") as Texture2D
			var frame: int = int(expected.get("frame", -1))
			var expected_region := Rect2(float(frame * CELL), 0.0, float(CELL), float(CELL))
			var cell_image := Image.new()
			if expected_texture != null and frame >= 0:
				var sheet_image: Image = expected_texture.get_image()
				if sheet_image != null and not sheet_image.is_empty():
					cell_image = sheet_image.get_region(Rect2i(frame * CELL, 0, CELL, CELL))
			var painted_bbox: Rect2i = cell_image.get_used_rect() if not cell_image.is_empty() else Rect2i()
			var painted_pixels: bool = painted_bbox.size.x > 0 and painted_bbox.size.y > 0
			var valid: bool = not expected.is_empty() and manager._approved_attack_active and \
				art.visible and art.material == null and art.region_enabled and \
				art.region_rect == expected_region and art.texture == expected_texture and \
				not manager._mortal_blade_sprite.visible and painted_pixels
			print("[DQ005 ANDROID BRIDGE] action=%s dir=%s state=%d active=%s visible=%s frame=%d bbox=%s painted=%s" % [
				_action_name(action_index), str(direction), int(rig.get("state")), str(manager._approved_attack_active),
				str(art.visible), frame, str(painted_bbox), str(valid)])
			if valid:
				passed += 1
			else:
				printerr("[DQ005 ANDROID BRIDGE] FAIL action=%s dir=%s sample_empty=%s texture_match=%s region_match=%s bbox=%s" % [
					_action_name(action_index), str(direction), str(expected.is_empty()),
					str(art.texture == expected_texture), str(art.region_rect == expected_region), str(painted_bbox)])
			rig.set("state", 0)
			rig.set("_charging", false)
			player.set("move_locked", false)
			manager._reset_mortal_sword_pose()
	print("[DQ005 ANDROID BRIDGE] %s painted bridge attacks=%d/20" % ["PASS" if passed == 20 else "FAIL", passed])
	get_tree().quit(0 if passed == 20 else 1)

func _action_name(action_index: int) -> String:
	match action_index:
		1: return "slash"
		2: return "rslash"
		3: return "windup"
		4: return "heavy"
		5: return "recover"
		_: return "unknown"

func _prepare_action(player: Node, rig: Node, action_index: int) -> void:
	rig.set("state", 0)
	rig.set("_charging", false)
	rig.set("_charge_t", 0.0)
	rig.set("_swing_t", 0.0)
	player.set("move_locked", false)
	match action_index:
		1:
			rig.call("_start_swing", 1)
			rig.set("_swing_t", float(rig.call("_swing_duration")) * 0.5)
		2:
			rig.call("_start_swing", 2)
			rig.set("_swing_t", float(rig.call("_swing_duration")) * 0.5)
		3:
			rig.set("_charging", true)
			rig.set("_charge_t", float(rig.get("charge_threshold")) * 0.5)
			player.set("move_locked", true)
		4:
			rig.call("_start_swing", 3)
			rig.set("_swing_t", float(rig.call("_swing_duration")) * 0.5)
		5:
			rig.set("state", 3)
			rig.set("_swing_t", float(rig.get("recover_time")) * 0.5)
			player.set("move_locked", true)
