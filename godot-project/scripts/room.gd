extends Node2D
## Reusable M1 room base for Reaper's Reaper.
##
## NOTE: intentionally no class_name (project convention — see save_system.gd).
## Each room scene: Node2D with this script, a Sprite2D "Background", an
## instanced Player, an instanced Luna, StaticBody2D "Walls", Area2D nodes in
## group "exit" (metadata: target_scene, target_room_id, spawn, lock_flag,
## locked_hint), Area2D nodes in group "trigger" (metadata: trigger_id,
## one_shot), and NPC instances.
##
## Room ID naming convention (for story-side layout docs): lowercase,
## chapter letter + number — "p1", "p2", "p3" (prologue), "c1", "c2" (ch1).
## GameState position dict carries {"room": room_id, "x": x, "y": y}.

signal room_ready

## Kanryu sighting beats V1-V4 (V2-V4 silent silhouettes; V1 carries the canon Luna line).
const KanryuSighting := preload("res://scripts/kanryu_sighting.gd")

## Room id, e.g. "p1". Must match GameState position "room".
@export var room_id: String = ""
## Playable bounds; camera limits lock to this rect.
@export var room_rect: Rect2 = Rect2(-640.0, -360.0, 1280.0, 720.0)
## Where the player spawns when not arriving via a saved position.
@export var player_spawn: Vector2 = Vector2.ZERO

var game_state = null  # GameState autoload or null (headless tests)
var player: CharacterBody2D = null
var luna: Node2D = null
var dialogue_box = null  # instanced DialogueBox, group "dialogue_box"


func _ready() -> void:
	game_state = get_node_or_null("/root/GameState")
	_place_player()
	_setup_camera()
	_setup_luna()
	_fit_background()
	dialogue_box = get_tree().get_first_node_in_group("dialogue_box")
	_connect_exits()
	_connect_triggers()
	_stats_record_room()
	_ach_on_entry()
	_speedrun_split()
	# Kanryu sighting beats V1-V4: silhouettes for beat rooms (V1 with canon Luna line), no-op elsewhere.
	KanryuSighting.attach_to(self)
	room_ready.emit()
	print("[ROOM] ", room_id, " ready, rect=", room_rect)


func _place_player() -> void:
	player = get_node_or_null("Player") as CharacterBody2D
	if player == null:
		push_warning("room.gd: no Player node in " + room_id)
		return
	var placed := false
	if game_state != null and game_state.has_method("get_position"):
		var pos: Dictionary = game_state.get_position()
		if str(pos.get("room", "")) == room_id:
			player.position = Vector2(float(pos.get("x", 0.0)), float(pos.get("y", 0.0)))
			placed = true
	if not placed:
		player.position = player_spawn


func _setup_camera() -> void:
	if player == null:
		return
	var cam := player.get_node_or_null("Camera2D") as Camera2D
	if cam == null:
		return
	cam.limit_left = int(room_rect.position.x)
	cam.limit_top = int(room_rect.position.y)
	cam.limit_right = int(room_rect.end.x)
	cam.limit_bottom = int(room_rect.end.y)
	cam.make_current()


func _setup_luna() -> void:
	luna = get_node_or_null("Luna")
	if luna == null or player == null:
		return
	if luna.has_method("set_target"):
		luna.set_target(player)
	# Luna starts beside the player unless a room placed her elsewhere.
	if luna.position == Vector2.ZERO:
		luna.position = player.position + Vector2(-40, 20)


func _fit_background() -> void:
	var bg := get_node_or_null("Background") as Sprite2D
	if bg == null or bg.texture == null:
		return
	var tex_size := bg.texture.get_size()
	if tex_size.x <= 0.0 or tex_size.y <= 0.0:
		return
	bg.position = room_rect.get_center()
	bg.scale = Vector2(room_rect.size.x / tex_size.x, room_rect.size.y / tex_size.y)


func _connect_exits() -> void:
	for node in get_tree().get_nodes_in_group("exit"):
		if node is Area2D and node.get_parent() == self:
			(node as Area2D).body_entered.connect(_on_exit_entered.bind(node))


func _connect_triggers() -> void:
	for node in get_tree().get_nodes_in_group("trigger"):
		if node is Area2D and node.get_parent() == self:
			(node as Area2D).body_entered.connect(_on_trigger_entered.bind(node))


func _on_exit_entered(body: Node2D, exit: Area2D) -> void:
	if not body.is_in_group("player"):
		return
	var lock_flag := str(exit.get_meta("lock_flag", ""))
	if lock_flag != "" and not _flag(lock_flag):
		_say_hint(str(exit.get_meta("locked_hint", "The way is shut.")))
		return
	var target := str(exit.get_meta("target_scene", ""))
	if target == "":
		_say_hint(str(exit.get_meta("locked_hint", "The way is shut.")))
		return
	# Persist where we are; the next room reads it back.
	var target_room_id := str(exit.get_meta("target_room_id", ""))
	# Demo boundary: block rooms beyond Ch1 in demo mode.
	if not DemoModeScript.room_allowed(target_room_id):
		_say_hint("The demo ends here. The full game continues beyond.")
		return
	if game_state != null and game_state.has_method("set_position"):
		var spawn: Vector2 = exit.get_meta("spawn", player.position)
		game_state.set_position(target_room_id, spawn.x, spawn.y)
	print("[ROOM] exit ", room_id, " -> ", target)
	get_tree().change_scene_to_file(target)


func _on_trigger_entered(body: Node2D, trigger: Area2D) -> void:
	if not body.is_in_group("player"):
		return
	var trigger_id := str(trigger.get_meta("trigger_id", ""))
	if trigger_id == "":
		return
	var one_shot := bool(trigger.get_meta("one_shot", true))
	if one_shot and _flag("trigger_" + trigger_id):
		return
	if one_shot:
		_set_flag("trigger_" + trigger_id)
	# Rooms override _on_room_trigger() for per-room behavior.
	_on_room_trigger(trigger_id, trigger)


## Override in room-specific scripts (or connect externally) for trigger logic.
func _on_room_trigger(_trigger_id: String, _trigger: Area2D) -> void:
	pass


func _flag(flag: String) -> bool:
	if game_state != null and game_state.has_method("get_flag"):
		return bool(game_state.get_flag(flag))
	return false


func _set_flag(flag: String, value: bool = true) -> void:
	if game_state != null and game_state.has_method("set_flag"):
		game_state.set_flag(flag, value)


## Achievement hook (null-safe: headless tests have no Achievements).
func _ach_unlock(id: String) -> void:
	var ach = get_node_or_null("/root/Achievements")
	if ach != null and ach.has_method("unlock"):
		ach.unlock(id)


## Room-entry achievement beats (idempotent — unlock() fires once).
func _ach_on_entry() -> void:
	match room_id:
		"hl1":
			# Steam "the_hollow" — trigger map: fires on hl1_entered
			# flag (first entry into HL1). Canonically depowered.
			if not _flag("hl1_entered"):
				_set_flag("hl1_entered", true)
		# e2 "return" fires on e2_fragment_planted (room_e2.tscn
		# lore_object), not on room entry.


## Speedrun splits: record a split when entering a new chapter.
func _speedrun_split() -> void:
	if game_state == null or not game_state.has_method("get_stat"):
		return
	# Map room_id prefix to chapter name.
	var chapter := ""
	if room_id.begins_with("p"):
		chapter = "prologue"
	elif room_id.begins_with("c"):
		chapter = "ch1"
	elif room_id.begins_with("h"):
		chapter = "ch2"
	elif room_id.begins_with("e"):
		chapter = "epilogue"
	# M3/M4 rooms use their own prefixes; map them.
	elif room_id.begins_with("g") or room_id.begins_with("f") or room_id.begins_with("d"):
		chapter = "ch" + str(_m3_chapter())
	elif room_id.begins_with("t") or room_id.begins_with("u") or room_id.begins_with("o"):
		chapter = "ch" + str(_m4_chapter())
	if chapter != "":
		SpeedrunScript.record_split(game_state, chapter)


func _m3_chapter() -> int:
	# M3 rooms: g1-g8 (Grove), f1-f3 (Forgehold), d1-d2 (Dragoni).
	# Rough mapping to chapters 6-12.
	return 9


func _m4_chapter() -> int:
	# M4 rooms: hl/t/u/gd/o/e (Hollow through epilogue).
	# Rough mapping to chapters 13-17.
	if room_id.begins_with("hl"):
		return 13
	if room_id.begins_with("t"):
		return 14
	if room_id.begins_with("u"):
		return 15
	if room_id.begins_with("gd"):
		return 16
	if room_id.begins_with("o") or room_id.begins_with("e"):
		return 17
	return 13


func _say_hint(text: String) -> void:
	if dialogue_box != null and dialogue_box.has_method("start_dialogue"):
		dialogue_box.start_dialogue([{"type": "direction", "text": text}])
	else:
		print("[ROOM] hint: ", text)


## Feed the achievement stat tracker (null-safe: headless tests have no Stats).
func _stats_record_room() -> void:
	if room_id == "":
		return
	var st = get_node_or_null("/root/Stats")
	if st != null and st.has_method("record_room"):
		st.record_room(room_id)


## --- Pause --------------------------------------------------------------
## Esc opens the pause menu — but never while a cutscene is playing (Esc is
## the hold-to-skip there), while dialogue is up, or while a menu is open.
## The actual open is deferred a frame so the pause menu's own _input can't
## see the same Esc press and instantly close what we just opened.

const PauseMenuScript := preload("res://scripts/pause_menu.gd")
const JournalScript := preload("res://scripts/journal.gd")
const PhotoModeScript := preload("res://scripts/photo_mode.gd")
const DemoModeScript := preload("res://scripts/demo_mode.gd")
const SpeedrunScript := preload("res://scripts/speedrun.gd")
const MemoriesScript := preload("res://scripts/memories.gd")
const MemoriesUIScript := preload("res://scripts/memories_ui.gd")


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and _can_pause():
		call_deferred("_open_pause_menu")
	# J opens Mollosar's Journal directly (same guards as pause).
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_J and _can_pause():
			call_deferred("_open_journal_direct")
		# P opens Photo Mode (same guards as pause).
		if event.keycode == KEY_P and _can_pause():
			call_deferred("_open_photo_mode")
		# C projects a memory — Whisper-line (burns 1 memory, 30s).
		if event.keycode == KEY_C and _can_pause():
			call_deferred("_open_projection_picker")


func _can_pause() -> bool:
	if get_tree().paused:
		return false
	if get_tree().get_first_node_in_group("pause_menu") != null:
		return false
	if get_tree().get_first_node_in_group("shop") != null:
		return false  # shop handles its own Esc
	if get_tree().get_first_node_in_group("shrine_menu") != null:
		return false  # shrine menu handles its own Esc
	var cs = get_tree().get_first_node_in_group("cutscene")
	if cs != null and cs.has_method("is_playing") and cs.is_playing():
		return false
	if dialogue_box != null and is_instance_valid(dialogue_box) and dialogue_box.visible:
		return false
	return true


func _open_pause_menu() -> void:
	if not _can_pause():
		return
	var menu = PauseMenuScript.new()
	menu.game_state = game_state
	get_tree().root.add_child(menu)
	menu._ready()
	menu.open()


## J hotkey: open the journal directly (pauses the tree like the menu does).
func _open_journal_direct() -> void:
	if not _can_pause():
		return
	if get_tree().get_first_node_in_group("journal") != null:
		return
	get_tree().paused = true
	var panel = JournalScript.new()
	panel.game_state = game_state
	get_tree().root.add_child(panel)
	panel._ready()
	panel.open()
	panel.closed.connect(_on_journal_closed)


func _on_journal_closed() -> void:
	get_tree().paused = false


## P hotkey: open Photo Mode (pauses the tree, free camera + filters).
func _open_photo_mode() -> void:
	if not _can_pause():
		return
	if get_tree().get_first_node_in_group("photo_mode") != null:
		return
	var photo = PhotoModeScript.new()
	photo.game_state = game_state
	photo.add_to_group("photo_mode")
	get_tree().root.add_child(photo)
	photo._ready()
	photo.exited.connect(_on_photo_mode_closed)
	photo.activate()


func _on_photo_mode_closed() -> void:
	for n in get_tree().get_nodes_in_group("photo_mode"):
		n.queue_free()


## C hotkey: Whisper-line projection. Opens the memory picker; the chosen
## memory is replayed one last time and burned. Projection lasts 30s —
## dungeon scripts read Memories.projection_active(game_state) for
## whisper-line puzzle hooks (future content; see memories.gd).
func _open_projection_picker() -> void:
	if not _can_pause():
		return
	if get_tree().get_first_node_in_group("memory_picker") != null:
		return
	if game_state == null or not MemoriesScript.can_project(game_state):
		return
	var ui = MemoriesUIScript.new()
	ui.add_to_group("memory_picker")
	get_tree().root.add_child(ui)
	ui._ready()
	ui.memory_picked.connect(_on_memory_picked)
	ui.pick(game_state)


func _on_memory_picked(key: String) -> void:
	for n in get_tree().get_nodes_in_group("memory_picker"):
		n.queue_free()
	if key == "" or game_state == null:
		return  # cancelled
	var mem: Dictionary = MemoriesScript.project(game_state, key)
	if mem.is_empty():
		return
	# Replay the flashback one last time through the dialogue box.
	var replay := "[A memory surfaces — bright, terrible, already fading: %s. %s]" % [
		str(mem.get("name", "")), str(mem.get("desc", ""))]
	if dialogue_box != null and is_instance_valid(dialogue_box) and dialogue_box.has_method("start_dialogue"):
		dialogue_box.start_dialogue([
			{"type": "direction", "text": replay},
			{"type": "direction", "text": "[The memory is gone. But for the next breaths, Mollosar is also elsewhere — listening at doors.]"},
		])
	else:
		print("[PROJECTION] ", replay)
