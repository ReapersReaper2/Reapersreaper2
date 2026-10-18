extends SceneTree
## DQ005: verify the actual first bridge scene with exported resource-pack files.
const Room := preload("res://scenes/room_p1.tscn")
const Clips := preload("res://scripts/form1_attack_clips.gd")
func _initialize() -> void:
	call_deferred("_run")
func _run() -> void:
	var bridge := Room.instantiate()
	root.add_child(bridge)
	var player = bridge.get_node_or_null("Player")
	if player == null:
		printerr("[DQ005 BRIDGE PACK] FAIL no player in room_p1")
		quit(1)
		return
	player.set_physics_process(false)
	var rig = player.get_node("ScytheRig")
	rig.set_physics_process(false)
	var manager = player.sprites
	print("[DQ005 BRIDGE PACK] loaded_clips=%d has_sprites=%s form=%d" % [manager._attack_clips.size(), str(manager.has_sprites()),manager.current_form()])
	if manager._attack_clips.size()!=20:
		printerr("[DQ005 BRIDGE PACK] FAIL no complete approved set in actual bridge scene")
		quit(1)
		return
	var good := true
	for dir in [Vector2.DOWN,Vector2.UP,Vector2.LEFT,Vector2.RIGHT]:
		player.facing=dir
		for attack in [1,2,3]:
			rig._start_swing(attack)
			rig._swing_t = rig._swing_duration() * 0.50
			player._physics_process(0.0)
			var art: Sprite2D = manager._sprite
			var expected := Clips.sample(manager._attack_clips, attack if attack<3 else 4, 0.50, dir)
			var valid := manager._approved_attack_active and art.material == null and not manager._mortal_blade_sprite.visible and art.texture == expected.get("texture", null)
			print("[DQ005 BRIDGE PACK] swing=%d dir=%s painted=%s" % [attack,str(dir),str(valid)])
			if not valid:
				good=false
			rig.cancel_charge()
			rig._advance()
			player._physics_process(0.0)
	print("[DQ005 BRIDGE PACK] %s live-swing bridge scene" % ("PASS" if good else "FAIL"))
	quit(0 if good else 1)
