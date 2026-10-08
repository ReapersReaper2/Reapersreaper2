extends "res://scripts/room.gd"
## C1 — The River (boat sequence, auto-poled). Form 2.
##
## NOTE: intentionally no class_name (project convention).
## Trigger "bounty_a": soul-bounty tutorial dialogue + a guidable wisp.
## The player must guide-touch it (E near it, stay close): on guided,
## the resolve dialogue plays and c1_bounty_done is set.
## Trigger "tentacle_b": spawns the tentacle (scaled dummy, 6 HP). On its
## death: scripted win dialogue, Vigor graze note, east exit unlocks.

const DUMMY_SCENE: PackedScene = preload("res://scenes/dummy.tscn")
const WISP_SCENE: PackedScene = preload("res://scenes/wisp.tscn")

## 06a canon (Ch1 Sc2 — The first bounty). Styx's "In."/"Collect." were
## already canon-identical and stay.
## The bounty plays in two beats: the intro (Luna explains guide-touch)
## fires on the trigger; the resolve plays when the player actually
## guides the wisp via the guide-touch mechanic (E near it, stay close).
const BOUNTY_INTRO_LINES: Array = [
	{"type": "dialogue", "character": "STYX", "text": "In."},
	{"type": "direction", "text": "A soul huddles on a half-drowned rock mid-river — a thin gray wisp of a person, flickering, lost. It doesn't look up."},
	{"type": "dialogue", "character": "LUNA", "text": "That's a stray. Souls slip off the current sometimes. They sit. They fade. Your job — our job — is to bring them in before they go out."},
	{"type": "dialogue", "character": "MOLLOSAR", "text": "With the scythe."},
	{"type": "dialogue", "character": "LUNA", "text": "It's not a weapon. Not for this. Think of it as… a shepherd's crook with delusions of grandeur. You hook the light, gentle, and you guide it. Like this — no, don't swing it, you'll scare it half to— okay. Okay, watch me. Slower. Softer."},
]

const BOUNTY_RESOLVE_LINES: Array = [
	{"type": "direction", "text": "Mollosar extends the scythe. The blade's edge catches the soul's light — not cutting, cradling. The wisp steadies, brightens a fraction, and drifts toward the boat."},
	{"type": "dialogue", "character": "MOLLOSAR", "text": "…It stopped shaking."},
	{"type": "dialogue", "character": "LUNA", "text": "They do that, when someone finally comes. Most of them have been waiting a long time."},
	{"type": "dialogue", "character": "MOLLOSAR", "text": "How long have I been—"},
	{"type": "dialogue", "character": "LUNA", "text": "Don't. Not yet. One thing at a time, big man."},
	{"type": "direction", "text": "The soul settles into the boat's lantern-light. Styx poles on without looking at it."},
	{"type": "dialogue", "character": "STYX", "text": "Collect."},
]

## 06a canon (Ch1 Sc3 — The tentacle). The [SPACE] prompt is wiring-side
## UX, not canon; the player fights the tentacle here (canon resolves it
## in one instinctive cut).
const TENTACLE_LINES: Array = [
	{"type": "direction", "text": "Mid-river. The water goes still — wrong still. Then the boat lurches as something enormous takes hold of it from below. A tentacle, black and glistening, rises over the gunwale."},
	{"type": "dialogue", "character": "LUNA", "text": "Oh, that's bad, that's very— MOLLOSAR!"},
	{"type": "dialogue", "character": "MOLLOSAR", "text": "[SPACE] to swing! Cut it before it takes the boat!"},
]

## 06a canon (Ch1 Sc3 — aftermath). Styx's "Hm." was already
## canon-identical and stays.
const TENTACLE_WIN_LINES: Array = [
	{"type": "direction", "text": "The tentacle is severed. Blue soul-light bursts where it was cut."},
	{"type": "dialogue", "character": "LUNA", "text": "…Did you practice that? In the, what, ten minutes you've been dead?"},
	{"type": "dialogue", "character": "MOLLOSAR", "text": "I don't know how I did that."},
	{"type": "direction", "text": "Styx looks at him — really looks at him — for the first time. Poles on."},
	{"type": "dialogue", "character": "STYX", "text": "Hm."},
	{"type": "direction", "text": "The fog takes the boat. Behind them, the severed tentacle sinks, trailing blue light."},
]

var _tentacle = null

## clean_hunt (Steam) tracking: whether the tentacle tutorial is running
## and whether the player has taken a hit since it started.
var _c1_tutorial_active := false
var _c1_tutorial_hit := false
var _c1_vigor_at_start := 0


func _on_room_trigger(trigger_id: String, trigger: Area2D) -> void:
	match trigger_id:
		"bounty_a":
			_play_bounty()
		"tentacle_b":
			_spawn_tentacle(trigger)
		"bellmaw":
			_start_bellmaw()


## Bellmaw — one-time boss on the river band (the old Gloomy Path fight,
## re-homed to C1). Fleeing leaves bellmaw_defeated unset so it re-triggers.
func _start_bellmaw() -> void:
	if _flag("bellmaw_defeated"):
		return
	var bm = get_node_or_null("/root/BattleManager")
	if bm == null or not bm.has_method("start_boss_battle"):
		push_warning("room_c1: BattleManager missing, Bellmaw skipped")
		return
	var pos := player.position if player != null else Vector2.ZERO
	print("[ROOM] c1: Bellmaw boss battle")
	bm.start_boss_battle("bellmaw", 12, room_id, pos, "bellmaw_defeated")


func _play_bounty() -> void:
	if dialogue_box != null and dialogue_box.has_method("start_dialogue"):
		dialogue_box.start_dialogue(BOUNTY_INTRO_LINES)
	# The real guide-touch mechanic: the wisp waits to be taken up.
	# E near it starts the guide; staying close fills the soothe meter.
	# The flag + resolve dialogue land on guided, not on the trigger.
	var wisp = WISP_SCENE.instantiate()
	wisp.position = Vector2(-1100, -120)
	add_child(wisp)
	if wisp.has_signal("guided"):
		wisp.guided.connect(_on_wisp_guided)
	print("[ROOM] c1: wisp spawned, awaiting guide-touch")


func _on_wisp_guided(_wisp) -> void:
	_set_flag("c1_bounty_done")
	if dialogue_box != null and dialogue_box.has_method("start_dialogue"):
		dialogue_box.start_dialogue(BOUNTY_RESOLVE_LINES)
	print("[ROOM] c1: wisp guided, bounty done")


func _spawn_tentacle(trigger: Area2D) -> void:
	if _tentacle != null:
		return
	_tentacle = DUMMY_SCENE.instantiate()
	_tentacle.position = trigger.position + Vector2(120, -60)
	_tentacle.scale = Vector2(1.7, 1.7)
	_tentacle.max_hp = 6
	add_child(_tentacle)
	if _tentacle.has_signal("died"):
		_tentacle.died.connect(_on_tentacle_died)
	# clean_hunt tracking: tutorial starts when the tentacle spawns.
	_c1_tutorial_active = true
	_c1_tutorial_hit = false
	if player != null and player.get("vigor") != null:
		_c1_vigor_at_start = int(player.get("vigor"))
	if player != null and player.has_signal("vigor_changed"):
		if not player.vigor_changed.is_connected(_on_c1_tutorial_vigor):
			player.vigor_changed.connect(_on_c1_tutorial_vigor)
	if dialogue_box != null and dialogue_box.has_method("start_dialogue"):
		dialogue_box.start_dialogue(TENTACLE_LINES)
	print("[ROOM] c1: tentacle spawned")


func _on_c1_tutorial_vigor(_vigor: int, _vigor_max: int) -> void:
	if not _c1_tutorial_active:
		return
	if player != null and player.get("vigor") != null:
		if int(player.get("vigor")) < _c1_vigor_at_start:
			_c1_tutorial_hit = true


func _on_tentacle_died(_dummy) -> void:
	_tentacle = null
	_set_flag("c1_tentacle_done")
	# Demo mode: the tentacle is the demo's final boss. Set the Wrath
	# cliffhanger (Wrath has taken the Kanryu bounty).
	var DemoModeScript = load("res://scripts/demo_mode.gd")
	if game_state != null:
		DemoModeScript.on_tentacle_down(game_state)
	# Steam "clean_hunt" — trigger map: tutorial_clean flag, set if the
	# player finishes the tentacle tutorial with zero hits taken.
	if _c1_tutorial_active and not _c1_tutorial_hit:
		_set_flag("tutorial_clean", true)
	_c1_tutorial_active = false
	if dialogue_box != null and dialogue_box.has_method("start_dialogue"):
		dialogue_box.dialogue_finished.connect(_unlock_east, CONNECT_ONE_SHOT)
		dialogue_box.start_dialogue(TENTACLE_WIN_LINES)
	else:
		_unlock_east()
	print("[ROOM] c1: tentacle defeated")


func _unlock_east() -> void:
	# The east exit's lock_flag was "c1_tentacle_done"; nothing more to do.
	pass
