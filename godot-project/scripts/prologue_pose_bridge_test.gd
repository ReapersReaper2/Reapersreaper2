extends SceneTree
## Two screenshot-driven upgrades: body-weighted mortal sword motion and
## irregular Bellhollow flagstones. No new combat hitboxes, colliders or
## LFS-only assets. Run in Godot 4.3:
## godot --headless --path godot-project --script res://scripts/prologue_pose_bridge_test.gd

const Bridge := preload("res://scripts/prologue_bridge_world.gd")
const Mollosar := preload("res://scripts/mollosar_sprites.gd")
const PlayerScene := preload("res://scenes/player.tscn")
const P1Scene := preload("res://scenes/room_p1.tscn")

var _checks: int = 0
var _failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var area := Rect2(-1280.0, -360.0, 2560.0, 720.0)
	var stones: Array = Bridge.flagstones_for(area)
	var repeat: Array = Bridge.flagstones_for(area)
	_check(stones.size() > 55 and stones.size() < 180,
		"flagstone count gives visual variety without excessive mobile draw calls")
	_check(stones.size() == repeat.size(),
		"bridge stone layout has stable deterministic geometry")
	_check(stones.size() > 0 and stones[0]["polygon"] == repeat[0]["polygon"],
		"reloading the same bridge never shuffles individual stones")
	var atypical := 0
	var total_points := 0
	var min_x := INF
	var max_x := -INF
	for stone_value in stones:
		var stone: Dictionary = stone_value
		var poly: PackedVector2Array = stone["polygon"]
		total_points += poly.size()
		if poly.size() >= 7:
			atypical += 1
		for p in poly:
			min_x = minf(min_x, p.x)
			max_x = maxf(max_x, p.x)
	_check(atypical == stones.size() and total_points >= stones.size() * 7,
		"each bridge stone is an irregular multi-point slab, not a rectangle")
	_check(min_x < -1200.0 and max_x > 1200.0,
		"stonework covers the full playable bridge width")
	_check(Bridge.flagstones_for(Rect2(0.0, 0.0, 0.0, 0.0)).is_empty(),
		"zero-size bounds do not create geometry")
	var room = P1Scene.instantiate()
	_check(room.get_node_or_null("WalkableBridge") != null,
		"authored mortal bridge scene uses the stone renderer")
	_check(room.get_node_or_null("BridgeRails") != null,
		"existing collision rail boundaries survive visual upgrade")
	_check(room.get_node_or_null("Luna") == null and room.get_node_or_null("ShrineP1") == null,
		"mortal scene canon remains intact during visual upgrade")
	room.free()

	var start := Mollosar.mortal_sword_pose(1, 0.0)
	var windup := Mollosar.mortal_sword_pose(1, 0.19)
	var impact := Mollosar.mortal_sword_pose(1, 0.51)
	var finish := Mollosar.mortal_sword_pose(1, 1.0)
	var reverse := Mollosar.mortal_sword_pose(2, 0.51)
	_check(is_zero_approx(float(start["lean"])) and
		is_equal_approx(float(start["scale"]), 1.0),
		"new mortal combo begins in the real sprite's neutral pose")
	_check(float(windup["lean"]) < -0.07 and float(windup["scale"]) < 1.0,
		"windup lowers and winds the body before impact")
	_check(float(impact["lean"]) > 0.0 and float(impact["shoulder"]) > 0.0,
		"mortal sword impact shifts body weight forward")
	_check(is_equal_approx(float(reverse["lean"]), -float(impact["lean"])) and
		is_equal_approx(float(reverse["shoulder"]), -float(impact["shoulder"])),
		"second sword strike counter-rotates the body")
	_check(absf(float(finish["lean"])) < 0.001 and
		is_equal_approx(float(finish["scale"]), 1.0),
		"recovery returns to the neutral idle body")
	for i in range(101):
		var pose: Dictionary = Mollosar.mortal_sword_pose(1, float(i) / 100.0)
		_check(absf(float(pose["lean"])) <= 0.104 and
			float(pose["scale"]) > 0.94 and float(pose["scale"]) < 1.05,
			"animation lean and squash never distort Mollosar excessively")

	# Live sprite integration: the player still owns its collision hitbox,
	# while the art turns around its foot contact on the bridge floor.
	var player = PlayerScene.instantiate()
	root.add_child(player)
	var manager = player.get("sprites")
	_check(manager != null and manager.has_sprites(),
		"approved Mollosar form 1 art is available for body posing")
	if manager != null and manager.has_sprites():
		var sprite = manager.get("_sprite") as Sprite2D
		var y0 := float(manager.get("_neutral_sprite_y"))
		_check(sprite != null, "mortal sprite manager provides an editable art layer")
		if sprite != null:
			manager.set_mortal_sword_pose(1, 0.52, Vector2.RIGHT)
			_check(absf(sprite.rotation) > 0.035,
				"visible sword slash drives real body rotation")
			var dist_to_feet: float = 64.0 - y0
			var simulated_foot: Vector2 = sprite.position + Vector2(
				0.0, dist_to_feet * sprite.scale.y / Mollosar.SPRITE_SCALE
			).rotated(sprite.rotation)
			_check(simulated_foot.distance_to(Vector2(0.0, 64.0)) < 3.2,
				"body shoulder turn keeps painted feet on the collision ground")
			manager.set_mortal_sword_pose(2, 0.52, Vector2.RIGHT)
			_check(sprite.rotation < 0.0,
				"second combo hit visibly twists the opposite way")
			manager.set_mortal_sword_pose(0, 0.0, Vector2.DOWN)
			_check(is_zero_approx(sprite.rotation) and
				sprite.position.is_equal_approx(Vector2(0.0, y0)) and
				sprite.scale.is_equal_approx(Vector2.ONE * Mollosar.SPRITE_SCALE),
				"combat end restores approved idle art without a pose leak")
	player.queue_free()

	if _failures == 0:
		print("[PROLOGUE POSE AND BRIDGE] PASS %d checks" % _checks)
	else:
		push_error("[PROLOGUE POSE AND BRIDGE] FAIL %d/%d" % [_failures, _checks])
	quit(1 if _failures > 0 else 0)

func _check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		push_error("[PROLOGUE POSE AND BRIDGE] " + message)
