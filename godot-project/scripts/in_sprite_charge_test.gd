extends SceneTree
## Charged sword is triggered on hold-release and uses the character's
## actual painted blade, not the detached ScytheVisual mesh.
## Godot 4.3: --headless --path godot-project --script res://scripts/in_sprite_charge_test.gd
const PlayerScene := preload("res://scenes/player.tscn")
const SpriteManager := preload("res://scripts/mollosar_sprites.gd")
const WeaponVisual := preload("res://scripts/scythe_visual.gd")
const TouchOverlay := preload("res://scripts/mobile_touch_overlay.gd")
const CombatTime := preload("res://scripts/combat_time.gd")

class HitTarget:
	extends Node2D
	var damage_taken: int = 0
	func take_hit(amount: int, _away: Vector2) -> void:
		damage_taken += amount

var _checks: int = 0
var _failed: int = 0
var _ready_count: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_check(not WeaponVisual.should_draw_external_weapon(true),
		"painted player never draws an independent swinging weapon")
	_check(WeaponVisual.should_draw_external_weapon(false),
		"temporary greybox has an emergency visible weapon fallback")
	for direction in ["down", "up", "left", "right"]:
		for swing in [1, 2]:
			_check(is_zero_approx(SpriteManager.mortal_blade_angle(direction, swing, 0.0)) and
				is_zero_approx(SpriteManager.mortal_blade_angle(direction, swing, 1.0)),
				"normal combo begins/ends with its actual painted sword: %s / %d" % [direction, swing])
	var pose := SpriteManager.mortal_sword_pose(3, 1.0)
	_check(float(pose["lean"]) < -0.10 and float(pose["shoulder"]) < -5.0,
		"holding attack visibly winds up painted arms and existing sword")
	_check(SpriteManager.mortal_blade_angle("down", 3, 1.0) != 0.0,
		"windup turns the source-painted blade around its wrist")
	_check(SpriteManager.mortal_sword_pose(4, 0.60).has("lean"),
		"charged strike drives a coherent full-body animation")
	var wound := SpriteManager.mortal_sword_pose(3, 1.0)
	var launch := SpriteManager.mortal_sword_pose(4, 0.0)
	_check(is_equal_approx(float(wound["lean"]), float(launch["lean"])) and
		is_equal_approx(float(wound["scale"]), float(launch["scale"])) and
		is_equal_approx(float(wound["shoulder"]), float(launch["shoulder"])),
		"charged release has no body snap or repeated windup")
	for direction in ["down", "up", "left", "right"]:
		_check(is_equal_approx(SpriteManager.mortal_blade_angle(direction, 3, 1.0),
			SpriteManager.mortal_blade_angle(direction, 4, 0.0)),
			"charged painted blade begins where the held hand finished: " + direction)
		_check(is_zero_approx(SpriteManager.mortal_blade_angle(direction, 4, 1.0)),
			"charged blade returns to its painted resting grip: " + direction)
	_check(float(SpriteManager.mortal_sword_pose(4, 0.67)["lean"]) > 0.1,
		"heavy cut drives the shoulders forward once before recovering")
	_check(is_zero_approx(float(SpriteManager.mortal_sword_pose(4, 1.0)["lean"])),
		"charged attack returns body to walk pose without a jump")

	var actor = PlayerScene.instantiate()
	root.add_child(actor)
	var rig = actor.get_node("ScytheRig")
	rig._ready()
	actor.facing = Vector2.RIGHT
	rig.charge_ready.connect(_on_ready)
	_check(rig.state == 0, "actor begins idle")

	# A tap is still the original fast combo attack (no added press lag).
	rig.begin_charge()
	_check(rig.is_charging() and actor.move_locked,
		"holding attack plants feet for grounded anticipation")
	rig._physics_process(0.12)
	_check(rig.charge_progress() > 0.2 and rig.charge_progress() < 0.3,
		"short press tracks a partial windup")
	rig.release_charge()
	_check(rig.state == 1 and not rig.is_charging(),
		"tap release commits a standard combo-capable slash")
	rig._advance()
	rig._advance()
	_check(rig.state == 0 and not actor.move_locked,
		"tap recovers and releases movement")

	# A half-second hold commits a heavier single swing on release.
	rig.begin_charge()
	rig._physics_process(0.25)
	rig._physics_process(0.25)
	_check(_ready_count == 1 and is_equal_approx(rig.charge_progress(), 1.0),
		"charge reaches ready once at 0.50 seconds")
	rig.release_charge()
	_check(rig.state == 4 and actor.move_locked,
		"releasing charged sword commits one heavy attack")
	_check(is_equal_approx(rig._swing_duration(), 0.66),
		"heavy strike has distinct paced follow-through")

	var target := HitTarget.new()
	target.add_to_group("hittable")
	root.add_child(target)
	target.global_position = actor.global_position + Vector2(70, 0)
	rig._swing_t = rig._swing_duration() * 0.50
	rig._try_hit(target)
	var first_damage: int = target.damage_taken
	var base_damage: int = maxi(1, int(round(float(rig._entry.get("damage_mult", 1.0)))))
	_check(first_damage > base_damage,
		"charged strike lands harder than the original tap at this weapon's tuning")
	rig._try_hit(target)
	_check(target.damage_taken == first_damage,
		"one hit per target per committed charged swing")
	rig._advance()
	rig._advance()
	_check(rig.state == 0 and not actor.move_locked,
		"charged slash finishes without trapping movement")

	rig.begin_charge()
	rig._physics_process(0.2)
	rig.cancel_charge()
	_check(rig.state == 0 and not rig.is_charging() and
		not actor.move_locked,
		"modal/focus interruptions cancel the windup without launching an attack")
	var touch = TouchOverlay.new()
	root.add_child(touch)
	rig.begin_charge()
	rig._physics_process(0.51)
	touch._cancel_gameplay_touches()
	_check(not rig.is_charging() and rig.state == 0 and
		not actor.move_locked,
		"Android app interruption cancels a full charge before finger-up")
	touch.queue_free()
	CombatTime.scale = 1.0
	target.queue_free()
	actor.queue_free()
	if _failed == 0:
		print("[IN SPRITE CHARGE] PASS %d checks" % _checks)
	else:
		push_error("[IN SPRITE CHARGE] FAIL %d/%d" % [_failed, _checks])
	quit(1 if _failed > 0 else 0)

func _on_ready() -> void:
	_ready_count += 1

func _check(ok: bool, description: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
		push_error("[IN SPRITE CHARGE] " + description)
