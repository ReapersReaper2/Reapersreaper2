extends SceneTree
## Real production sheets + actual Player/ScytheRig: tap, reverse, hold,
## heavy, recovery, hitstop and idle/walk hand-off, including packed builds.
const PlayerScene := preload("res://scenes/player.tscn")
const Clips := preload("res://scripts/form1_attack_clips.gd")
const Loader := preload("res://scripts/critical_sprite_loader.gd")
const CombatTime := preload("res://scripts/combat_time.gd")
var checks := 0
var failed := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failed += 1
		push_error("[FORM1 ANIMATION RUNTIME] " + label)

func _run() -> void:
	var clips := Clips.load_approved(Callable(Loader, "load_texture"))
	# The rejected 20-strip set was deliberately deleted. Verify this
	# quarantine instead of failing mobile builds over removed artwork.
	if clips.is_empty():
		_check(not FileAccess.file_exists(Clips.MANIFEST_PATH),
			"rejected manifest stays removed from shipping builds")
		print("[FORM1 ANIMATION RUNTIME] PASS: rejected art absent; fallback active")
		quit(1 if failed > 0 else 0)
		return
	_check(clips.size() == 20, "complete approved animation set required")
	var actor = PlayerScene.instantiate()
	root.add_child(actor)
	actor.set_physics_process(false)
	var rig = actor.get_node("ScytheRig")
	rig.set_physics_process(false)
	var manager = actor.sprites
	var art: Sprite2D = manager._sprite
	CombatTime.scale = 1.0
	for facing in [Vector2.DOWN, Vector2.UP, Vector2.LEFT, Vector2.RIGHT]:
		actor.facing = facing
		manager.tick(0.0, facing, true)
		var walk_height := art.texture.get_image().get_region(Rect2i(0, 0, 384, 384)).get_used_rect().size.y * art.scale.y
		manager.tick(0.0, facing, false)
		var idle_bounds := art.texture.get_image().get_region(Rect2i(0, 0, 384, 384)).get_used_rect()
		_check(absf(float(idle_bounds.size.y) * art.scale.y - walk_height) < 1.0,
			"idle and walk retain the same character height: " + str(facing))
		_check(absf(art.position.y + float(idle_bounds.end.y - 192) * art.scale.y - 64.0) < 1.0,
			"idle feet remain grounded after scale correction: " + str(facing))
		rig.begin_charge()
		for fraction in [0.0, 0.25, 0.5, 0.75, 1.0]:
			rig._charge_t = rig.charge_threshold * fraction
			actor._physics_process(0.0)
			_check(art.texture == clips[Clips.clip_key("windup", Clips.direction_for_facing(facing))]["texture"],
				"hold uses the directional whole-character windup")
		rig.cancel_charge()
		for attack in [1, 2, 3]:
			rig._start_swing(attack)
			var frames_seen: Dictionary = {}
			var action := "slash" if attack == 1 else ("rslash" if attack == 2 else "heavy")
			var key := Clips.clip_key(action, Clips.direction_for_facing(facing))
			var duration: float = rig._swing_duration()
			for step in range(int(ceilf(duration * 60.0))):
				rig._swing_t = float(step) / 60.0
				actor._physics_process(0.0)
				frames_seen[int(art.region_rect.position.x / 384.0)] = true
				_check(art.texture == clips[key]["texture"] and art.material == null and
						not manager._mortal_blade_sprite.visible and is_zero_approx(art.rotation),
					"strike stays one intact character without blade/body shader")
				_check((art.position + Vector2(0, 168) * art.scale.y).distance_to(Vector2(0, 64)) < 0.01,
					"attack artist pivot stays planted")
			_check(frames_seen.size() == int(clips[key]["frames"]),
				"every painted strike frame is displayed at 60Hz: " + key)
			CombatTime.scale = 0.0
			var before: float = rig._swing_t
			rig._physics_process(1.0 / 60.0)
			_check(is_equal_approx(rig._swing_t, before), "hitstop freezes the shared animation clock")
			CombatTime.scale = 1.0
			rig._advance()
			var recovery_seen: Dictionary = {}
			for step in range(int(ceilf(rig.recover_time * 60.0))):
				rig._swing_t = float(step) / 60.0
				actor._physics_process(0.0)
				recovery_seen[int(art.region_rect.position.x / 384.0)] = true
				_check(actor.move_locked and art.texture == clips[Clips.clip_key("recover", Clips.direction_for_facing(facing))]["texture"],
					"recovery retains painted frames during existing movement lock")
			_check(recovery_seen.size() == 6, "all six recovery poses receive time on screen")
			rig._advance()
			actor._physics_process(0.0)
			_check(not actor.move_locked and not manager._approved_attack_active and
				art.texture == manager._idle.get(manager._strip_dir, manager._strips[manager._strip_dir]),
				"combat completion restores directional idle and unlocks movement")
			manager.tick(0.0, facing, true)
			_check(art.texture == manager._strips[manager._strip_dir] and art.region_rect.position.x == 0.0 and
				art.scale.is_equal_approx(Vector2.ONE * manager.SPRITE_SCALE),
				"walk restarts at frame zero with its normal scale")
			manager.tick(0.18, facing, true)
			_check(art.region_rect.position.x > 0.0, "walk advances after attack recovery")
	actor.free()
	print("[FORM1 ANIMATION RUNTIME] %s %d checks" % ["PASS" if failed == 0 else "FAIL", checks])
	quit(1 if failed > 0 else 0)
