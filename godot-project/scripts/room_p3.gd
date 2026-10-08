extends "res://scripts/room.gd"
## P3 — Black Sand Shore (Form 2 unlock, movement tutorial).
##
## NOTE: intentionally no class_name (project convention).
## On first entry: Luna's intro dialogue plays, then Form 2 unlocks
## (GameState.set_form(2)) and the east exit to C1 opens. No combat here.

## 06a canon (Prologue Sc3 — Black sand). Form 2 unlock follows.
const INTRO_LINES: Array = [
	{"type": "dialogue", "character": "LUNA", "text": "—up. Come on, get up."},
	{"type": "direction", "text": "He sits up. The robe slides off one bony shoulder. He stares at his hands — at the bones of his hands."},
	{"type": "dialogue", "character": "MOLLOSAR", "text": "…No."},
	{"type": "dialogue", "character": "LUNA", "text": "That's the spirit. Up. The river doesn't wait, and neither does the paperwork."},
	{"type": "dialogue", "character": "MOLLOSAR", "text": "I didn't… I never held one of these."},
	{"type": "direction", "text": "He looks at the scythe lying beside his hand."},
	{"type": "dialogue", "character": "LUNA", "text": "You do now. Congratulations on the promotion. It's terrible. You'll hate it."},
	{"type": "direction", "text": "He stands. The robe pools around his feet; he gathers it up with a dignity that doesn't quite survive the extra fabric."},
	{"type": "dialogue", "character": "MOLLOSAR", "text": "Where is this."},
	{"type": "dialogue", "character": "LUNA", "text": "The far shore. Everybody wakes up here eventually. Most of them scream longer than you did, so — well done."},
	{"type": "dialogue", "character": "MOLLOSAR", "text": "The bells. I could hear—"},
	{"type": "dialogue", "character": "LUNA", "text": "Yeah. They all hear something. Come on. If we stand here much longer something will try to eat us, and you are currently the least intimidating thing on this beach."},
]


func _ready() -> void:
	super._ready()
	# Defer so the room (and dialogue box) is fully settled first.
	_play_intro.call_deferred()


func _play_intro() -> void:
	if _flag("p3_luna_intro_done"):
		return
	if dialogue_box != null and dialogue_box.has_method("start_dialogue"):
		dialogue_box.dialogue_finished.connect(_on_intro_finished, CONNECT_ONE_SHOT)
		dialogue_box.start_dialogue(INTRO_LINES)
	else:
		_on_intro_finished()


func _on_intro_finished() -> void:
	_set_flag("p3_luna_intro_done")
	if game_state != null and game_state.has_method("set_form"):
		game_state.set_form(2)
	_ach_unlock("form2_unlocked")
	print("[ROOM] p3: Form 2 unlocked")


## Achievement hook (null-safe: headless tests have no Achievements).
func _ach_unlock(id: String) -> void:
	var ach = get_node_or_null("/root/Achievements")
	if ach != null and ach.has_method("unlock"):
		ach.unlock(id)
