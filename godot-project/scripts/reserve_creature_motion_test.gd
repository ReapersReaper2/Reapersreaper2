extends SceneTree
## Living Reserve residents: deterministic motion, grounded shadows, and
## stable awareness. Runs without imported artwork or Git LFS.
## godot --headless --path godot-project --script res://scripts/reserve_creature_motion_test.gd

const Motion := preload("res://scripts/reserve_creature_motion.gd")
const Resident := preload("res://scripts/reserve_creature.gd")

var _checks := 0
var _failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	for style in range(4):
		for i in range(250):
			var t := float(i) * 0.09
			var motion: Dictionary = Motion.sample(style, t, 1.37, 0.5)
			var next: Dictionary = Motion.sample(style, t + 0.01, 1.37, 0.5)
			var offset: Vector2 = motion["offset"]
			_check(offset.length() <= Motion.MAX_WANDER + 0.001,
				"creature motion never leaves authored territory")
			_check(float(motion["lift"]) >= 0.0 and
				float(motion["lift"]) <= Motion.MAX_LIFT,
				"creature motion never lifts beyond safe limits")
			_check(absf(float(motion["tilt"])) <= 0.141,
				"lean stays readable without toppling art")
			_check(offset.distance_to(next["offset"]) < 2.0,
				"every motion style travels continuously at frame boundaries")

	_check(Motion.sample(Motion.Style.ROOTED, 2.0)["offset"].length() < 6.0,
		"rooted creature breathes but does not wander")
	var max_hop := 0.0
	var drift_reach := 0.0
	var prowling := 0.0
	for i in range(160):
		var t := float(i) * 0.08
		max_hop = maxf(max_hop, float(Motion.sample(Motion.Style.HOP, t)["lift"]))
		drift_reach = maxf(drift_reach,
			absf(float((Motion.sample(Motion.Style.DRIFT, t)["offset"] as Vector2).x)))
		prowling = maxf(prowling,
			absf(float((Motion.sample(Motion.Style.PROWL, t)["offset"] as Vector2).x)))
	_check(max_hop > 20.0, "Spinehopper visibly leaves the ground")
	_check(drift_reach > 12.0, "Wispwillow visibly drifts")
	_check(prowling > 18.0, "Dragonthorn visibly paces")
	_check(Motion.sample(Motion.Style.HOP, 1.2, 0.4) ==
		Motion.sample(Motion.Style.HOP, 1.2, 0.4),
		"ambient motion is deterministic")
	_check(Motion.sample(Motion.Style.ROOTED, 1.0, 0.0, 1.0)["breath"] >
		Motion.sample(Motion.Style.ROOTED, 1.0, 0.0, 0.0)["breath"],
		"attention visibly increases breathing")

	# Runtime fixture: resident, sensor and shadow must stay synchronized
	# through bobbing and terrain-scale sprite transforms.
	var room := Node2D.new()
	room.name = "MotionTestRoom"
	root.add_child(room)
	var creatures := Node2D.new()
	creatures.name = "Creatures"
	room.add_child(creatures)
	var image := Image.create(96, 96, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.25, 0.45, 0.25, 1.0))
	var resident = Resident.new()
	resident.name = "Spinehopper"
	resident.texture = ImageTexture.create_from_image(image)
	resident.motion_style = Motion.Style.HOP
	resident.position = Vector2(230, 100)
	resident.scale = Vector2(0.5, 0.5)
	creatures.add_child(resident)
	_check(resident.get_node_or_null("ContactShadow") != null,
		"every living resident gets a ground-contact shadow")
	_check(resident.get("_sensor") != null,
		"every living resident creates an awareness sensor")
	var foot_floor := float((resident.get("_shadow") as Node2D).global_position.y)
	for i in range(110):
		resident._process(0.05)
		var shadow := resident.get("_shadow") as Node2D
		_check(is_instance_valid(shadow) and shadow.z_as_relative == false,
			"contact shadow remains at absolute garden depth")
		_check(resident.position.distance_to(Vector2(230, 100)) <= 55.0,
			"visible motion stays local to the encounter")
		_check((resident.get("_sensor") as Node2D).position.is_equal_approx(resident.position),
			"awareness follows creature movement instead of lagging")
		_check(absf(shadow.global_position.y - foot_floor) <= 9.0,
			"shadow follows the ground rather than the jump")
	var player := CharacterBody2D.new()
	player.add_to_group("player")
	room.add_child(player)
	resident._on_body_entered(player)
	_check(resident.is_player_in_range(), "existing interaction still works")
	_check(float(resident.get("_startle_time")) > 0.0,
		"noticed creature gives a brief physical acknowledgement")
	resident.set_selected(true)
	_check(resident.get("_selected"), "single-creature selection still works")
	_check(resident.trigger_interaction(), "creature observation still works")
	_check(float(resident.get("_reaction_time")) > 0.0,
		"interaction retains visible response")
	resident._on_body_exited(player)
	_check(not resident.is_player_in_range(), "leaving awareness restores idle state")
	room.queue_free()

	if _failures == 0:
		print("[RESERVE MOTION] PASS %d checks" % _checks)
	else:
		push_error("[RESERVE MOTION] FAIL %d/%d" % [_failures, _checks])
	quit(1 if _failures > 0 else 0)

func _check(ok: bool, description: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		push_error("[RESERVE MOTION] " + description)
