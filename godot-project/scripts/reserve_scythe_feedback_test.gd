extends SceneTree
## Reserve weapon feedback: directional startle is visible but never damages,
## observes, captures, or changes the creature ledger.
## godot --headless --path godot-project --script res://scripts/reserve_scythe_feedback_test.gd

const Guide := preload("res://scripts/reserve_guide.gd")
const Resident := preload("res://scripts/reserve_creature.gd")

class FakePlayer:
	extends CharacterBody2D
	var facing: Vector2 = Vector2.RIGHT

class FakeRig:
	extends Node2D
	signal swing_started(index: int)

var _checks := 0
var _failed := 0
var _interactions := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_check(Guide.within_swing_reaction_arc(Vector2.ZERO, Vector2.RIGHT,
		Vector2(100, 0), 150.0, 75.0), "front resident lies in weapon arc")
	_check(not Guide.within_swing_reaction_arc(Vector2.ZERO, Vector2.RIGHT,
		Vector2(-100, 0), 150.0, 75.0), "behind resident is excluded")
	_check(not Guide.within_swing_reaction_arc(Vector2.ZERO, Vector2.RIGHT,
		Vector2(0, 100), 150.0, 75.0), "side resident is excluded")
	_check(not Guide.within_swing_reaction_arc(Vector2.ZERO, Vector2.RIGHT,
		Vector2(200, 0), 150.0, 75.0), "distant resident is excluded")
	_check(not Guide.within_swing_reaction_arc(Vector2.ZERO, Vector2.RIGHT,
		Vector2.ZERO, 0.0, 75.0), "zero-radius arc cannot startle")

	var room := Node2D.new()
	room.name = "ReserveScytheTestRoom"
	root.add_child(room)
	var player := FakePlayer.new()
	player.name = "Player"
	room.add_child(player)
	var rig := FakeRig.new()
	rig.name = "ScytheRig"
	player.add_child(rig)
	var residents := Node2D.new()
	residents.name = "Creatures"
	room.add_child(residents)

	# Explicit texture prevents loading artwork or depending on LFS.
	var pixels := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	pixels.fill(Color(0.3, 0.6, 0.4))
	var sample_texture := ImageTexture.create_from_image(pixels)
	var front := _resident("Front", Vector2(100, 0), sample_texture)
	var behind := _resident("Behind", Vector2(-100, 0), sample_texture)
	var side := _resident("Side", Vector2(0, 100), sample_texture)
	var far := _resident("Far", Vector2(240, 0), sample_texture)
	for resident in [front, behind, side, far]:
		residents.add_child(resident)
		resident.interacted.connect(_record_interaction)

	var guide = Guide.new()
	guide.name = "ReserveGuide"
	room.add_child(guide)
	_check(rig.get_signal_connection_list("swing_started").size() == 1,
		"guide connects to actual weapon swing signal")
	var observed_before: int = guide._observed_count()
	rig.swing_started.emit(1)
	_check(float(front.get("_scythe_recoil_time")) > 0.0,
		"resident in front starts visible recoil")
	_check(float(behind.get("_scythe_recoil_time")) == 0.0,
		"resident behind is not startled")
	_check(float(side.get("_scythe_recoil_time")) == 0.0,
		"resident outside swing angle is not startled")
	_check(float(far.get("_scythe_recoil_time")) == 0.0,
		"resident outside radius is not startled")
	_check(str(guide.get("_highlight_text")).contains("USE TO OBSERVE"),
		"HUD teaches observation action without invented dialogue")
	_check(_interactions == 0 and guide._observed_count() == observed_before,
		"swing does not mark seen, trigger observation, or capture")

	var initial_x: float = front.position.x
	front._process(0.16)
	_check(front.position.x > initial_x + 6.0,
		"startle creates a readable horizontal recoil")
	front._process(1.0)
	_check(is_zero_approx(float(front.get("_scythe_recoil_time"))),
		"startle decays and does not persist in save state")
	_check(front.modulate == Color.WHITE,
		"resident returns to normal color after recoil")

	player.facing = Vector2.LEFT
	rig.swing_started.emit(2)
	_check(float(behind.get("_scythe_recoil_time")) > 0.0,
		"second combo swing reacts to current player facing")
	_check(_interactions == 0 and guide._observed_count() == observed_before,
		"combo swing still does not observe or capture")

	room.queue_free()
	if _failed == 0:
		print("[RESERVE SCYTHE FEEDBACK TEST] PASS %d checks" % _checks)
	else:
		push_error("[RESERVE SCYTHE FEEDBACK TEST] FAIL %d/%d" % [_failed, _checks])
	quit(1 if _failed > 0 else 0)

func _resident(name_id: String, at: Vector2, image: Texture2D) -> Sprite2D:
	var resident := Resident.new()
	resident.name = name_id
	resident.position = at
	resident.texture = image
	return resident

func _record_interaction(_creature: Node2D) -> void:
	_interactions += 1

func _check(ok: bool, description: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
		push_error("[RESERVE SCYTHE FEEDBACK TEST] " + description)
