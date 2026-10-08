extends "res://scripts/room.gd"
## Shared Act 2 (Ch9-Ch12 + SQ1) scene wiring for all M3 rooms:
## f1-f3 (Forgehold), g1-g2 (Grove), s1-s2 (Warrens/sloths), c2 (cache),
## v1 (Astral Village), b1 (Bellmaw), d1-d2 (Mount Dragoni).
##
## NOTE: intentionally no class_name (project convention).
##
## On first entry, each room plays its 06b scenes (data/dialogue_06b.md) in
## doc order through the room's DialogueBox, one shot per scene
## (flag d06b_seen_<room>_<scene_index>). [TRIGGER:] entries route through
## Dialogue06B.apply_trigger(); > **Choice:** branches play only the chosen
## branch via Dialogue06B.split_at_choice(). The Bellmaw continuity lock
## (Luna ABSENT) hides Luna for those scenes.
##
## Lore objects and NPCs keep their existing placeholder lines; the 06b
## scenes play on room entry so every scene is reachable in its room.

const D06B := preload("res://scripts/dialogue_06b.gd")
## MemoriesScript is inherited from room.gd (parent const).

var _d06b_queue: Array = []
var _d06b_scene: Dictionary = {}
var _d06b_split: Dictionary = {}
var _d06b_awaiting_branch := false
var _d06b_playing := false
var _d06b_luna_hidden := false


func _ready() -> void:
	super._ready()
	if dialogue_box != null:
		if dialogue_box.has_signal("trigger_fired"):
			if not dialogue_box.trigger_fired.is_connected(_on_d06b_trigger_fired):
				dialogue_box.trigger_fired.connect(_on_d06b_trigger_fired)
		if dialogue_box.has_signal("choice_made"):
			if not dialogue_box.choice_made.is_connected(_on_d06b_choice_made):
				dialogue_box.choice_made.connect(_on_d06b_choice_made)
		if dialogue_box.has_signal("dialogue_finished"):
			if not dialogue_box.dialogue_finished.is_connected(_on_d06b_dialogue_finished):
				dialogue_box.dialogue_finished.connect(_on_d06b_dialogue_finished)
	_d06b_collect_scenes()
	call_deferred("_d06b_play_next")


func _d06b_collect_scenes() -> void:
	var entries: Array = D06B.load_entries()
	if entries.is_empty():
		return
	for sc in D06B.scenes_for_room(entries, room_id):
		var key := "d06b_seen_%s_%d" % [room_id, int((sc as Dictionary).get("scene_index", 0))]
		if not _flag(key):
			_d06b_queue.append(sc)


func _d06b_ctx() -> Dictionary:
	return {"game_state": game_state, "room": self, "scene": _d06b_scene,
		"choice_id": D06B.choice_id_for_scene(_d06b_scene)}


func _d06b_play_next() -> void:
	if _d06b_playing:
		return
	if _d06b_queue.is_empty():
		_d06b_restore_luna()
		return
	_d06b_scene = _d06b_queue.pop_front()
	_d06b_split = D06B.split_at_choice(_d06b_scene.get("entries", []))
	_d06b_apply_luna_lock()
	_d06b_filter_memory_options()
	_d06b_playing = true
	_d06b_awaiting_branch = not (_d06b_split.get("choice", {}) as Dictionary).is_empty()
	var run: Array = (_d06b_split.get("pre", []) as Array).duplicate()
	if _d06b_awaiting_branch:
		run.append(_d06b_split.get("choice", {}))
	if run.is_empty():
		_d06b_finish_scene()
		return
	if dialogue_box != null and dialogue_box.has_method("start_dialogue"):
		dialogue_box.start_dialogue(run)
	else:
		# Headless / no box: apply triggers directly so flags still land.
		for e in run:
			if (e as Dictionary).get("type") == "trigger":
				D06B.apply_trigger(str((e as Dictionary).get("text", "")), _d06b_ctx())
		_d06b_finish_scene()


## Bellmaw continuity lock: Luna is ABSENT for the whole sequence.
func _d06b_apply_luna_lock() -> void:
	var want_hidden := D06B.scene_hides_luna(_d06b_scene)
	if want_hidden == _d06b_luna_hidden:
		return
	_d06b_luna_hidden = want_hidden
	if luna != null and luna.has_method("set_visible"):
		luna.set_visible(not want_hidden)
	elif luna != null:
		(luna as Node2D).visible = not want_hidden


func _d06b_restore_luna() -> void:
	if not _d06b_luna_hidden:
		return
	_d06b_luna_hidden = false
	if luna != null:
		(luna as Node2D).visible = true


## Inn trade (Astral Village): only offer memories Mollosar still holds.
## Already-spent memories are never re-offered. Fail-safe: if every option
## were somehow spent, leave the choice untouched rather than breaking it.
func _d06b_filter_memory_options() -> void:
	if D06B.choice_id_for_scene(_d06b_scene) != "memory":
		return
	var choice: Dictionary = _d06b_split.get("choice", {})
	if choice.is_empty():
		return
	var gs = (_d06b_ctx() as Dictionary).get("game_state")
	var kept: Array = []
	for o in (choice.get("options", []) as Array):
		var letter := str((o as Dictionary).get("key", ""))
		var mkey := MemoriesScript.trade_key_for_letter(letter)
		if mkey != "" and MemoriesScript.has(gs, mkey):
			kept.append(o)
	if not kept.is_empty():
		choice["options"] = kept


func _on_d06b_trigger_fired(trigger_text: String) -> void:
	if not _d06b_playing:
		return
	D06B.apply_trigger(trigger_text, _d06b_ctx())


func _on_d06b_choice_made(option: Dictionary) -> void:
	if not _d06b_playing or not _d06b_awaiting_branch:
		return
	_d06b_awaiting_branch = false
	D06B.apply_choice(option, _d06b_ctx())
	var branches: Dictionary = _d06b_split.get("branches", {})
	var key := str(option.get("key", ""))
	var run: Array = (branches.get(key, []) as Array).duplicate()
	run.append_array(_d06b_split.get("post", []))
	# The box auto-finished after the choice; start the branch as a new run.
	_d06b_split = {"pre": run, "choice": {}, "branches": {}, "post": [], "order": []}
	if run.is_empty():
		_d06b_finish_scene()
		return
	if dialogue_box != null and dialogue_box.has_method("start_dialogue"):
		dialogue_box.start_dialogue(run)
	else:
		for e in run:
			if (e as Dictionary).get("type") == "trigger":
				D06B.apply_trigger(str((e as Dictionary).get("text", "")), _d06b_ctx())
		_d06b_finish_scene()


func _on_d06b_dialogue_finished() -> void:
	if not _d06b_playing:
		return
	if _d06b_awaiting_branch:
		# The pre-choice run ended at the choice UI; the branch comes next
		# via _on_d06b_choice_made. Don't advance the queue yet.
		return
	_d06b_finish_scene()


func _d06b_finish_scene() -> void:
	_d06b_playing = false
	_d06b_awaiting_branch = false
	if not _d06b_scene.is_empty():
		var key := "d06b_seen_%s_%d" % [room_id, int(_d06b_scene.get("scene_index", 0))]
		_set_flag(key)
	_d06b_scene = {}
	call_deferred("_d06b_play_next")
