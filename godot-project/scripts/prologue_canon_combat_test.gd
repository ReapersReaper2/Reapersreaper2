extends SceneTree
## Player-footage regression: the mortal prologue must precede Luna, the
## bridge has no underworld shrine, UI owns movement, and the sword has
## a readable strike with NO purple hitbox/debug sector.
## godot --headless --path godot-project --script res://scripts/prologue_canon_combat_test.gd

const P1Scene := preload("res://scenes/room_p1.tscn")
const P3Scene := preload("res://scenes/room_p3.tscn")
const RoomScript := preload("res://scripts/room.gd")
const P1Script := preload("res://scripts/room_p1.gd")
const P3Script := preload("res://scripts/room_p3.gd")
const SwordVisual := preload("res://scripts/scythe_visual.gd")
const SwordRig := preload("res://scripts/scythe.gd")
const PlayerScript := preload("res://scripts/player.gd")
const DialogueScene := preload("res://scenes/dialogue_box.tscn")
const Collapse := preload("res://scripts/cutscene_p2.gd")

var _checks := 0
var _failed := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var p1 = P1Scene.instantiate()
	_check(p1.get_node_or_null("Luna") == null,
		"Luna cannot appear on the mortal Bellhollow Bridge")
	_check(p1.get_node_or_null("ShrineP1") == null,
		"mortal bridge does not offer Soul Vault, rest or underworld travel")
	_check(p1.get_node_or_null("Mira") != null,
		"Mira remains part of the mortal prologue")
	_check(p1.get_node_or_null("WaveSpawner") != null,
		"invader tutorial and sword combat remain wired")
	p1.free()
	var p3 = P3Scene.instantiate()
	_check(p3.get_node_or_null("Luna") != null,
		"Luna's first real scene is the post-death Black Sand Shore")
	p3.free()
	_check(not RoomScript.luna_is_allowed("p1") and
		not RoomScript.luna_is_allowed("p2") and RoomScript.luna_is_allowed("p3"),
		"shared rooms disallow Luna in mortal prologue scenes")
	_check(P3Script.INTRO_LINES.size() > 0 and
		str(P3Script.INTRO_LINES[0].get("character", "")) == "LUNA",
		"post-death intro still begins with Luna")
	var beats: Array = Collapse.steps()
	var death_index := -1
	var arrival_index := -1
	for i in range(beats.size()):
		var beat: Dictionary = beats[i]
		if str(beat.get("flag", "")) == "prologue_complete":
			death_index = i
		if str(beat.get("path", "")) == "res://scenes/room_p3.tscn":
			arrival_index = i
	_check(death_index >= 0 and arrival_index > death_index,
		"collapse and mortal death complete before arrival at Luna's shore")

	_check(P1Script.objective_text(false, false, true).contains("JOYSTICK"),
		"mobile opening explains joystick")
	_check(P1Script.objective_text(false, true, true).contains("TAP SWORD"),
		"mobile combat teaches the sword, never scythe/space")
	_check(not P1Script.objective_text(false, true, true).contains("SCYTHE"),
		"mortal sword is never mislabeled as a scythe")
	_check(P1Script.objective_text(false, true, false).contains("SPACE"),
		"keyboard uses the actual attack binding")
	_check(P1Script.objective_text(true, true, true).contains("EAST"),
		"bridge-clear guidance points toward the tower")
	var mobile_lines: Array = P1Script.tutorial_lines_for(true)
	var desktop_lines: Array = P1Script.tutorial_lines_for(false)
	_check(str(mobile_lines.back().get("text", "")).contains("[SWORD]"),
		"mortal story tutorial shows SWORD on touchscreens")
	_check(str(desktop_lines.back().get("text", "")).contains("[SPACE]"),
		"keyboard story tutorial retains SPACE instruction")

	var rig = SwordRig.new()
	_check(not rig.show_debug_arc,
		"neon purple attack-sector debug drawing is disabled")
	rig.free()
	var early := SwordVisual.sword_stroke_angle(1, 0.05)
	var wound := SwordVisual.sword_stroke_angle(1, 0.19)
	var contact := SwordVisual.sword_stroke_angle(1, 0.54)
	var settled := SwordVisual.sword_stroke_angle(1, 0.97)
	_check(wound < early and wound < -1.0,
		"sword draws back before the strike")
	_check(contact > 0.0 and settled > 0.0,
		"sword sweeps forward then follows through")
	_check(is_equal_approx(SwordVisual.sword_stroke_angle(2, 0.54), -contact),
		"second combo strike travels in the opposite direction")
	_check(SwordVisual.sword_trail_opacity(0.0) == 0.0 and
		SwordVisual.sword_trail_opacity(0.40) > 0.0 and
		SwordVisual.sword_trail_opacity(1.0) == 0.0,
		"brief steel glint only during active swing, not resting")

	var player = PlayerScript.new()
	root.add_child(player)
	var box = DialogueScene.instantiate()
	box.add_to_group("dialogue_box")
	root.add_child(box)
	_check(not player._gameplay_modal_open(),
		"player begins with control when no dialogue or menu is open")
	var first := [{"type": "dialogue", "character": "MIRA", "text": "First text"}]
	var second := [{"type": "dialogue", "character": "SOLDIER", "text": "Hijack attempt"}]
	_check(box.start_dialogue(first), "first dialogue can start")
	_check(not box.start_dialogue(second), "second dialogue cannot hijack the first")
	_check(str(box.get("_entries")[0]["text"]) == "First text",
		"original speaker and line are preserved")
	_check(player._gameplay_modal_open(), "dialogue blocks gameplay input")
	Input.action_press("move_right")
	player.velocity = Vector2(80, 0)
	player._physics_process(1.0 / 60.0)
	_check(player.velocity == Vector2.ZERO, "dialogue immediately stops joystick movement")
	Input.action_release("move_right")
	box.force_close()
	_check(not player._gameplay_modal_open(), "closing dialogue restores input")
	var modal := CanvasLayer.new()
	modal.add_to_group("shrine_menu")
	root.add_child(modal)
	_check(player._gameplay_modal_open(), "shrine menu locks player input")
	Input.action_press("move_right")
	player._physics_process(1.0 / 60.0)
	_check(player.velocity == Vector2.ZERO, "shrine UI prevents moving behind menu")
	Input.action_release("move_right")
	modal.remove_from_group("shrine_menu")
	modal.free()
	_check(not player._gameplay_modal_open(), "closing shrine menu restores play")
	box.free()
	player.free()
	if _failed == 0:
		print("[PROLOGUE CANON / SWORD] PASS %d checks" % _checks)
	else:
		push_error("[PROLOGUE CANON / SWORD] FAIL %d/%d checks" % [_failed, _checks])
	quit(1 if _failed > 0 else 0)

func _check(ok: bool, description: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
		push_error("[PROLOGUE CANON / SWORD] " + description)
