extends Area2D
## Bounty Board: the side-quest hub for Reaper's Reaper (unlocks in H1).
##
## NOTE: intentionally no class_name (project convention).
## E to open when the player is in range. Lists takeable contracts from
## data/contracts.json (accept with Enter/click), tracks accepted ones
## with live objective progress, and turns in completed contracts for
## Soul Credits. The Kanryu entry stays sealed — NEVER takable.
## Shows both hunters' tallies (Mollosar's grows as you turn in work).
## Opening the board sets the h1_board_read tutorial flag.

const BOARD_PATH := "res://data/bounty_board.json"
const Contracts = preload("res://scripts/contracts.gd")

var game_state = null

var _player_in_range: bool = false
var _open: bool = false
var _built: bool = false
var _layer: CanvasLayer = null
var _list: VBoxContainer = null
var _detail: Label = null
var _flash: Label = null
var _buttons: Array = []  # contract ids in button order


const BONE := Color(0.92, 0.90, 0.86)
const GOLD := Color(0.95, 0.80, 0.45)
const RED := Color(0.85, 0.30, 0.25)
const DIM := Color(0.45, 0.44, 0.42)
const GOOD := Color(0.55, 0.85, 0.55)


static func load_board() -> Dictionary:
	if not FileAccess.file_exists(BOARD_PATH):
		return {}
	var f := FileAccess.open(BOARD_PATH, FileAccess.READ)
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	return parsed if parsed is Dictionary else {}


func _ready() -> void:
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	if not body_exited.is_connected(_on_body_exited):
		body_exited.connect(_on_body_exited)
	if game_state == null and is_inside_tree():
		game_state = get_node_or_null("/root/GameState")


func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		_player_in_range = true
		$Prompt.visible = true


func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		_player_in_range = false
		$Prompt.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if not _player_in_range:
		return
	if _open:
		if event.is_action_pressed("ui_cancel"):
			get_viewport().set_input_as_handled()
			close_board()
		return
	if event.is_action_pressed("interact"):
		get_viewport().set_input_as_handled()
		open_board.call_deferred()


func open_board() -> void:
	if _open:
		return
	_open = true
	$Prompt.visible = false
	_build()
	_fill()
	_layer.visible = true
	if game_state != null and game_state.has_method("set_flag"):
		game_state.set_flag("h1_board_read")
	_focus_first()


func close_board() -> void:
	_open = false
	if _layer != null:
		_layer.visible = false
	if _player_in_range:
		$Prompt.visible = true


func is_open() -> bool:
	return _open


func _build() -> void:
	if _built:
		return
	_built = true
	_layer = CanvasLayer.new()
	_layer.layer = 12
	_layer.visible = false
	# bounty_board has no scene; attach to the tree root so it survives.
	if is_inside_tree():
		get_tree().root.add_child(_layer)
	else:
		add_child(_layer)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.75)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_layer.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_layer.add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	center.add_child(box)
	var title := Label.new()
	title.text = "BOUNTY BOARD"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 36)
	title.add_theme_color_override("font_color", GOLD)
	box.add_child(title)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 4)
	box.add_child(_list)
	_detail = Label.new()
	_detail.add_theme_font_size_override("font_size", 17)
	_detail.add_theme_color_override("font_color", BONE)
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.custom_minimum_size = Vector2(640, 0)
	box.add_child(_detail)
	_flash = Label.new()
	_flash.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_flash.add_theme_font_size_override("font_size", 18)
	_flash.add_theme_color_override("font_color", GOOD)
	box.add_child(_flash)
	var hint := Label.new()
	hint.text = "[Enter] accept / turn in — [Esc] close"
	hint.add_theme_font_size_override("font_size", 16)
	hint.add_theme_color_override("font_color", DIM)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(hint)


func _fill() -> void:
	for c in _list.get_children():
		c.queue_free()
	_buttons.clear()
	_detail.text = ""
	var board := load_board()
	if board.is_empty():
		var l := Label.new()
		l.text = "The board is bare."
		l.add_theme_color_override("font_color", DIM)
		_list.add_child(l)
		return
	# Hunter tallies (Mollosar's grows as contracts are turned in).
	var acts: Dictionary = board.get("acts", {})
	var act: Dictionary = acts.get("act1", {})
	var done_count := Contracts.turned_in_ids(game_state).size()
	for hunter in ["mollosar", "wrath"]:
		var h: Dictionary = act.get(hunter, {})
		var n := int(h.get("completed", 0))
		if hunter == "mollosar":
			n += done_count
		var row := Label.new()
		row.text = "%s — %d completed. %s" % [hunter.capitalize(), n, str(h.get("note", ""))]
		row.add_theme_font_size_override("font_size", 19)
		row.add_theme_color_override("font_color", BONE)
		row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.custom_minimum_size = Vector2(640, 0)
		_list.add_child(row)
	# Daily Hunt (retention): today's deterministic hunt, 1/day.
	_fill_daily_hunt()
	# Contracts header.
	var sep := HSeparator.new()
	_list.add_child(sep)
	var chead := Label.new()
	chead.text = "CONTRACTS"
	chead.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	chead.add_theme_font_size_override("font_size", 22)
	chead.add_theme_color_override("font_color", GOLD)
	_list.add_child(chead)
	for c in Contracts.load_contracts():
		_add_contract_button(c)
	# The Kanryu entry: permanent, sealed, never takable.
	var k: Dictionary = board.get("kanryu", {})
	var sep2 := HSeparator.new()
	_list.add_child(sep2)
	var kt := Label.new()
	kt.text = str(k.get("name", "KANRYU"))
	kt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	kt.add_theme_font_size_override("font_size", 28)
	kt.add_theme_color_override("font_color", RED)
	_list.add_child(kt)
	var kd := Label.new()
	# Demo cliffhanger: Wrath has taken the Kanryu bounty.
	var DemoModeScript = load("res://scripts/demo_mode.gd")
	if DemoModeScript.wrath_took_kanryu(game_state):
		kd.text = "TAKEN — BY WRATH\nThe board turns over. A new name is burned at the top:\nWRATH has taken the Kanryu bounty.\n\nTo be continued in the full game."
	else:
		kd.text = "SEALED — NOT FOR YOU\nTerms: %s\n%s" % [
			str(k.get("terms", "")),
			str(k.get("note", "")),
		]
	kd.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	kd.add_theme_font_size_override("font_size", 18)
	kd.add_theme_color_override("font_color", DIM)
	kd.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	kd.custom_minimum_size = Vector2(640, 0)
	_list.add_child(kd)


func _fill_daily_hunt() -> void:
	var DailyHuntsScript = load("res://scripts/daily_hunts.gd")
	var sep := HSeparator.new()
	_list.add_child(sep)
	var head := Label.new()
	head.text = "TODAY'S HUNT"
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_theme_font_size_override("font_size", 22)
	head.add_theme_color_override("font_color", GOLD)
	_list.add_child(head)
	var hunt: Dictionary = DailyHuntsScript.hunt_for(DailyHuntsScript.today_string())
	var mods: Array = hunt["modifiers"]
	var mod_names: Array = []
	for m in mods:
		mod_names.append(DailyHuntsScript.modifier_name(m))
	var info := Label.new()
	info.text = "%s — Lv%d\nModifiers: %s\nReward: %d Soul Credits" % [
		str(hunt["target_name"]), int(hunt["level"]),
		", ".join(mod_names), int(hunt["reward"]),
	]
	info.add_theme_font_size_override("font_size", 18)
	info.add_theme_color_override("font_color", BONE)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.custom_minimum_size = Vector2(640, 0)
	_list.add_child(info)
	var best: Dictionary = DailyHuntsScript.best_for(str(hunt["date"]), game_state)
	if not best.is_empty():
		var bl := Label.new()
		bl.text = "Your best today: %d pts (%ds)" % [int(best["score"]), int(best["seconds"])]
		bl.add_theme_font_size_override("font_size", 16)
		bl.add_theme_color_override("font_color", GOOD)
		_list.add_child(bl)
	var b := Button.new()
	if DailyHuntsScript.is_active(game_state):
		b.text = "✕ Abandon today's hunt"
	else:
		b.text = "▶ Begin today's hunt"
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.flat = true
	b.focus_mode = Control.FOCUS_ALL
	b.custom_minimum_size = Vector2(640, 30)
	b.add_theme_font_size_override("font_size", 19)
	b.add_theme_color_override("font_color", GOLD)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_focus_color", Color.WHITE)
	b.pressed.connect(_on_daily_hunt_pressed)
	_list.add_child(b)


func _on_daily_hunt_pressed() -> void:
	var DailyHuntsScript = load("res://scripts/daily_hunts.gd")
	if DailyHuntsScript.is_active(game_state):
		DailyHuntsScript.abandon_hunt(game_state)
		_flash.text = "Hunt abandoned."
	else:
		var hunt: Dictionary = DailyHuntsScript.start_hunt(game_state)
		var creature_id: String = DailyHuntsScript.battle_creature_id(str(hunt.get("target_id", "snapling")))
		var is_boss := bool(hunt.get("is_boss", false))
		var level := int(hunt.get("level", 5))
		var started := _spawn_daily_hunt(creature_id, level, is_boss)
		close_board()
		if started:
			# The battle runs now; the board refreshes when it reopens.
			return
		# Couldn't spawn the encounter — roll the hunt back.
		DailyHuntsScript.abandon_hunt(game_state)
		_flash.text = "Couldn't start the hunt — no battler ready."
	_fill()


## Spawn today's hunt target as a real encounter: wild targets fight in
## the seamless in-room layer, boss targets in the staged battle arena.
## Returns false when there's no BattleManager or the start is refused
## (battle already active, no conscious party creature).
func _spawn_daily_hunt(creature_id: String, level: int, is_boss: bool) -> bool:
	var tree := get_tree()
	if tree == null:
		return false
	var room_id := ""
	var pos := Vector2.ZERO
	var scene: Node = tree.current_scene
	if scene != null and "room_id" in scene:
		room_id = str(scene.get("room_id"))
	var player: Node = tree.get_first_node_in_group("player")
	if player is Node2D:
		pos = (player as Node2D).position
	var bm = get_node_or_null("/root/BattleManager")
	if bm == null or not bm.has_method("start_daily_hunt_battle"):
		return false
	return bool(bm.call("start_daily_hunt_battle", creature_id, level, is_boss, room_id, pos))


func _add_contract_button(c: Dictionary) -> void:
	var cid: String = str(c.get("id", ""))
	var st: String = Contracts.status(game_state, cid)
	var mark: String = str({"available": "○", "accepted": "◔", "ready": "●", "done": "✓", "locked": "✕"}.get(st, "?"))
	var color: Color = BONE
	if st == "done":
		color = GOOD
	elif st == "ready":
		color = GOLD
	elif st == "locked":
		color = DIM
	var b := Button.new()
	b.text = "%s %s — %d Soul Credits" % [mark, str(c.get("name", "?")), int(c.get("reward_credits", 0))]
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.flat = true
	b.focus_mode = Control.FOCUS_ALL
	b.custom_minimum_size = Vector2(640, 30)
	b.add_theme_font_size_override("font_size", 19)
	b.add_theme_color_override("font_color", color)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_focus_color", Color.WHITE)
	b.pressed.connect(_on_contract_pressed.bind(cid))
	b.mouse_entered.connect(_show_contract_detail.bind(cid))
	b.focus_entered.connect(_show_contract_detail.bind(cid))
	_list.add_child(b)
	_buttons.append(cid)


func _show_contract_detail(cid: String) -> void:
	if _detail == null:
		return
	var c := Contracts.get_contract(cid)
	if c.is_empty():
		return
	var st := Contracts.status(game_state, cid)
	var lines: Array = ["== " + str(c.get("name", "?")) + " =="]
	lines.append("From: " + str(c.get("giver", "")))
	lines.append(str(c.get("description", "")))
	for p in Contracts.objectives_progress(game_state, cid):
		var o: Dictionary = p
		lines.append("%s [%d/%d] %s" % ["✓" if bool(o.get("done", false)) else "·", int(o.get("current", 0)), int(o.get("target", 1)), str(o.get("text", ""))])
	if st == "available":
		lines.append("Press Enter to accept this contract.")
	elif st == "ready":
		lines.append("Complete! Press Enter to turn it in.")
	elif st == "locked":
		lines.append(_lock_reason(c))
	_detail.text = "\n".join(lines)


func _lock_reason(c: Dictionary) -> String:
	var req_flag: String = str(c.get("required_flag", ""))
	if req_flag != "" and not _flag(req_flag):
		return "Locked: read the bounty board first."
	var req_c: String = str(c.get("required_contract", ""))
	if req_c != "":
		var prev := Contracts.get_contract(req_c)
		return "Locked: finish \"%s\" first." % str(prev.get("name", req_c))
	return "Locked."


func _flag(flag: String) -> bool:
	if game_state != null and game_state.has_method("get_flag"):
		return bool(game_state.get_flag(flag))
	return false


func _on_contract_pressed(cid: String) -> void:
	_flash.text = ""
	var st := Contracts.status(game_state, cid)
	if st == "available":
		if Contracts.accept(game_state, cid):
			_flash.text = "Contract accepted: " + str(Contracts.get_contract(cid).get("name", ""))
		else:
			_flash.text = "Could not accept that contract."
	elif st == "ready":
		var res := Contracts.turn_in(game_state, cid)
		if bool(res.get("ok", false)):
			var items: Dictionary = res.get("items", {})
			var extra := ""
			if not items.is_empty():
				var parts: Array = []
				for k in items:
					parts.append("%dx %s" % [int(items[k]), str(k)])
				extra = " + " + ", ".join(parts)
			_flash.text = "Turned in! +%d Soul Credits%s" % [int(res.get("credits", 0)), extra]
		else:
			_flash.text = "Not ready to turn in yet."
	else:
		_show_contract_detail(cid)
	_fill()
	# queue_free() from _fill is deferred — refocus after it settles.
	_refocus.call_deferred(cid)


func _focus_first() -> void:
	for child in _list.get_children():
		if child is Button and (child as Button).focus_mode != Control.FOCUS_NONE:
			(child as Button).grab_focus()
			_show_contract_detail(_buttons[0] if not _buttons.is_empty() else "")
			return


func _refocus(cid: String) -> void:
	for i in _buttons.size():
		if str(_buttons[i]) == cid:
			var kids := _list.get_children()
			var bi := 0
			for child in kids:
				if child is Button:
					if bi == i:
						(child as Button).grab_focus()
						_show_contract_detail(cid)
						return
					bi += 1
