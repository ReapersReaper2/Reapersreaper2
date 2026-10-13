extends "res://scripts/room.gd"
## P1 — Bellhollow Bridge (combat tutorial). Mortal Mollosar, Form 1.
##
## NOTE: intentionally no class_name (project convention).
## Trigger "tutorial": fires the 4-line sword tutorial once, then the
## player fights the 2 placed dummies (stand-in "invaders").
## Trigger "bridge_end": plays the P2 tower-collapse cutscene, which ends
## by transitioning to room_p3.

const CutsceneScript := preload("res://scripts/cutscene.gd")
const CutsceneP2 := preload("res://scripts/cutscene_p2.gd")

var _waves_started: bool = false
var _objective_label: Label = null


func _ready() -> void:
	super._ready()
	_build_objective_hud()


## Small always-visible gameplay guidance, not Muse-owned story dialogue.
## Keep it above the opening's scenery and outside the player's path.
func _build_objective_hud() -> void:
	if _objective_label != null:
		return
	var layer := CanvasLayer.new()
	layer.name = "ObjectiveHUD"
	layer.layer = 12
	add_child(layer)
	var backing := ColorRect.new()
	backing.color = Color(0.045, 0.065, 0.075, 0.78)
	backing.position = Vector2(19, 16)
	backing.size = Vector2(530, 53)
	backing.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(backing)
	_objective_label = Label.new()
	_objective_label.position = Vector2(36, 28)
	_objective_label.size = Vector2(500, 32)
	_objective_label.add_theme_font_size_override("font_size", 20)
	_objective_label.add_theme_color_override("font_color", Color(0.92, 0.83, 0.64))
	_objective_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_objective_label)
	_refresh_objective()


func _process(_delta: float) -> void:
	_refresh_objective()


## Form 1 is MORTAL: the action is a sword strike, not a scythe.
## Platform tests must not depend on the host machine being Android.
static func objective_text(cleared: bool, fighting: bool, touch: bool) -> String:
	if cleared:
		return "OBJECTIVE   EAST  →  Reach the tower"
	if fighting:
		return "OBJECTIVE   Defend the bridge  ·  TAP SWORD" if touch else (
			"OBJECTIVE   Defend the bridge  ·  SPACE = SWORD")
	return "OBJECTIVE   Cross the bridge  ·  JOYSTICK" if touch else (
		"OBJECTIVE   Cross the bridge  ·  WASD")


static func tutorial_lines_for(touch: bool) -> Array:
	var lines_out := TUTORIAL_LINES.duplicate(true)
	if touch:
		for entry in lines_out:
			if str(entry.get("text", "")).contains("[SPACE]"):
				entry["text"] = str(entry["text"]).replace("[SPACE]", "[SWORD]")
	return lines_out


func _is_mobile_input() -> bool:
	return OS.has_feature("android") or OS.has_feature("ios") or OS.has_feature("mobile") or DisplayServer.is_touchscreen_available()


func _refresh_objective() -> void:
	if _objective_label == null:
		return
	_objective_label.text = objective_text(_flag("p1_bridge_cleared"), _waves_started, _is_mobile_input())

## 06a canon (Prologue Sc1). The [SPACE] prompt is wiring-side UX, not canon.
const TUTORIAL_LINES: Array = [
	{"type": "direction", "text": "Villagers stream across the bridge, running. Smoke hangs low; the far sound of fighting."},
	{"type": "dialogue", "character": "MIRA", "text": "Please — the tower! They're inside the—"},
	{"type": "dialogue", "character": "MOLLOSAR", "text": "Go. Don't stop until the bells stop ringing."},
	{"type": "direction", "text": "Invaders break from the smoke — then another. Sword, weight, the feel of a man at his peak."},
	{"type": "dialogue", "character": "MOLLOSAR", "text": "[SPACE] to swing. Cut them down before they reach the villagers."},
]


func _on_room_trigger(trigger_id: String, _trigger: Area2D) -> void:
	match trigger_id:
		"tutorial":
			if dialogue_box != null and dialogue_box.has_method("start_dialogue"):
				dialogue_box.start_dialogue(tutorial_lines_for(_is_mobile_input()))
			_start_waves_after_dialogue()
		"bridge_end":
			if _flag("p2_collapse_seen"):
				return
			if not _flag("p1_bridge_cleared"):
				_say_hint("Invaders still press from the west — the bridge isn't clear.")
				return
			_play_collapse()


## Waves begin once the tutorial dialogue finishes (the initial_delay on
## the spawner gives the last line room to land).
func _start_waves_after_dialogue() -> void:
	if _waves_started:
		return
	_waves_started = true
	var spawner = get_node_or_null("WaveSpawner")
	if spawner == null or not spawner.has_method("start_waves"):
		return
	if dialogue_box != null and dialogue_box.has_signal("dialogue_finished"):
		dialogue_box.dialogue_finished.connect(spawner.start_waves, CONNECT_ONE_SHOT)
	else:
		spawner.start_waves()


## P2 tower collapse: letterbox, pan, rumble, fade, then room_p3.
## The cutscene node goes on the tree root so its fade survives the
## P2->P3 scene change and can fade back in on the new scene.
func _play_collapse() -> void:
	var cs = CutsceneScript.new()
	get_tree().root.add_child(cs)
	cs.cutscene_finished.connect(_on_collapse_finished)
	var cam = null
	if player != null:
		cam = player.get_node_or_null("Camera2D")
	cs.play(CutsceneP2.steps(), {
		"player": player,
		"luna": luna,
		"camera": cam,
		"dialogue_box": dialogue_box,
		"game_state": game_state,
	})


func _on_collapse_finished() -> void:
	print("[ROOM] p2 collapse cutscene finished")
