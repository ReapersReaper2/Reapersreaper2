extends SceneTree
## Charged sword is triggered on hold-release and uses the character's
## actual painted blade, not the detached ScytheVisual mesh.
## Godot 4.3: --headless --path godot-project --script res://scripts/in_sprite_charge_test.gd
const PlayerScene := preload("res://scenes/player.tscn")
const SpriteManager := preload("res://scripts/mollosar_sprites.gd")
const WeaponVisual := preload("res://scripts/scythe_visual.gd")
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
	var pose := SpriteManager.mortal_sword_pose(3, 1.0)
	_check(float(pose["lean"]) < -0.10 and float(pose["shoulder"]) < -5.0,
		"holding attack visibly winds up painted arms and existing sword")
	_check(SpriteManager.mortal_blade_angle("down", 3, 1.0) != 0.0,
		"windup turns the source-painted blade around its wrist")
	_check(SpriteManager.mortal_sword_pose(4, 0.60).has("lean"),
		"charged strike drives a coherent full-body animation")

	var actor = PlayerScene.instantiate()
	root.add_child(actor)
	var rig = actor.get_node("ScytheRig")
	rig._ready()
	actor.facing = Vector2.RIGHT
	rig.charge_ready.connect(_on_ready)
	_check(rig.state == rig.State.IDLE, "actor begins idle")

	# A tap is still the original fast combo attack (no added press lag).
	rig.begin_charge()
	_check(rig.is_charging() and actor.move_locked,
		"holding attack plants feet for grounded anticipation")
	rig._physics_process(0.12)
	_check(rig.charge_progress() > 0.2 and rig.charge_progress() < 0.3,
		"short press tracks a partial windup")
	rig.release_charge()
	_check(rig.state == rig.State.SWING1 and not rig.is_charging(),
		"tap release commits a standard combo-capable slash")
	rig._advance()
	rig._advance()
	_check(rig.state == rig.State.IDLE and not actor.move_locked,
		"tap recovers and releases movement")

	# A half-second hold commits a heavier single swing on release.
	rig.begin_charge()
	rig._physics_process(0.25)
	rig._physics_process(0.25)
	_check(_ready_count == 1 and is_equal_approx(rig.charge_progress(), 1.0),
		"charge reaches ready once at 0.50 seconds")
	rig.release_charge()
	_check(rig.state == rig.State.CHARGED_SWING and actor.move_locked,
		"releasing charged sword commits one heavy attack")
	_check(is_equal_approx(rig._swing_duration(), 0.66),
		"heavy strike has distinct paced follow-through")

	var target := HitTarget.new()
	target.add_to_group("hittable")
	root.add_child(target)
	target.global_position = actor.global_position + Vector2(70, 0)
	rig._swing_t = rig._swing_duration() * 0.50
	rig._try_hit(target)
	_check(target.damage_taken >= 2,
		"charged strike lands harder than the original one-damage tap")
	rig._try_hit(target)
	_check(target.damage_taken <= 3,
		"one hit per target per committed charged swing")
	rig._advance()
	rig._advance()
	_check(rig.state == rig.State.IDLE and not actor.move_locked,
		"charged slash finishes without trapping movement")

	rig.begin_charge()
	rig._physics_process(0.2)
	rig.cancel_charge()
	_check(rig.state == rig.State.IDLE and not rig.is_charging() and
		not actor.move_locked,
		"modal/focus interruptions cancel the windup without launching an attack")
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
