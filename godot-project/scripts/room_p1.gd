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
				dialogue_box.start_dialogue(TUTORIAL_LINES)
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
