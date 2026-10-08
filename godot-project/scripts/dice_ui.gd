extends CanvasLayer
## Dead Man's Dice UI (code-built, stall_ui.gd pattern).
##
## NOTE: intentionally no class_name (project convention).
## CanvasLayer added to the tree root by dice_table_interact.gd; pauses the
## tree while open (process_mode ALWAYS). Code-drawn dice pips (DieFace),
## table select, roll/bank/push flow, opponent turn animation, payouts.
##
## Controls: Space/Enter or pad A = roll, X or pad X = bank,
## Esc or pad B = push / leave. Mouse: click buttons.
## Flavor text: table hints, Wrath intro/flip, Murray hints, the generic-flow
## lines (select, buy-in denied, bust/bank/push rolls, opponent turns, pot
## lines — keyed in dice_game.gd FLOW_LINES so re-cuts never touch tests),
## and the three per-reason lock lines (back-room, blend gate, quiet gate)
## are story-bot text (2026-10-05). Remaining [WIRING] holds (no revision
## text yet): deals line, push line, blend/quiet win lines, play-again line,
## Wrath/Latch taunts.

signal closed

const DiceGame = preload("res://scripts/dice_game.gd")

var game_state = null

var _open := false
var _built := false
var _table := "copper"
var _game = null  # DiceGame instance
var _opp := {}  # current opponent dict (name, taunt, loss_line)
var _mode := "select"  # select | beat | playing | over
var _flip_page := 0
var _beat_lines: Array = []
var _beat_page := 0
var _beat_resume := ""  # "game" | "close" | ""
var _pending_sit := ""  # Murray's first-sit line, shown after the intro beat

var _title: Label
var _opp_name: Label
var _opp_taunt: Label
var _portrait: ColorRect
var _score: Label
var _round: Label
var _dice_row: HBoxContainer
var _dice_faces: Array = []
var _msg: Label
var _hint: Label
var _table_row: HBoxContainer
var _table_buttons := {}
var _btn_roll: Button
var _btn_bank: Button
var _btn_push: Button
var _btn_leave: Button


## A single die: white rounded square with pips, drawn in _draw().
class DieFace extends Control:
	var value := 1
	var dimmed := false

	func _ready() -> void:
		custom_minimum_size = Vector2(64, 64)

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		var col := Color(0.94, 0.92, 0.88) if not dimmed else Color(0.55, 0.54, 0.52)
		draw_rect(r, col, true)
		draw_rect(r, Color(0.2, 0.18, 0.16), false, 3.0)
		var pip := Color(0.16, 0.14, 0.12)
		var c := size * 0.5
		var o := size.x * 0.26
		var pts := {
			1: [c],
			2: [c + Vector2(-o, -o), c + Vector2(o, o)],
			3: [c + Vector2(-o, -o), c, c + Vector2(o, o)],
			4: [c + Vector2(-o, -o), c + Vector2(o, -o), c + Vector2(-o, o), c + Vector2(o, o)],
			5: [c + Vector2(-o, -o), c + Vector2(o, -o), c, c + Vector2(-o, o), c + Vector2(o, o)],
			6: [c + Vector2(-o, -o), c + Vector2(o, -o), c + Vector2(-o, 0), c + Vector2(o, 0), c + Vector2(-o, o), c + Vector2(o, o)],
		}
		for p in pts.get(value, []):
			draw_circle(p, 6.0, pip)


func _ready() -> void:
	add_to_group("dice_table")
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 14
	_build()
	visible = false


func _build() -> void:
	if _built:
		return
	_built = true
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.015, 0.03, 0.9)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(680, 600)
	center.add_child(panel)
	var margin := MarginContainer.new()
	for m in ["margin_left", "margin_right"]:
		margin.add_theme_constant_override(m, 24)
	for m in ["margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(m, 16)
	panel.add_child(margin)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	_title = Label.new()
	_title.text = "DEAD MAN'S DICE"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 30)
	_title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.45))
	vbox.add_child(_title)

	_table_row = HBoxContainer.new()
	_table_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_table_row.add_theme_constant_override("separation", 12)
	vbox.add_child(_table_row)

	var opp_row := HBoxContainer.new()
	opp_row.add_theme_constant_override("separation", 12)
	vbox.add_child(opp_row)
	_portrait = ColorRect.new()
	_portrait.custom_minimum_size = Vector2(72, 72)
	_portrait.color = Color(0.25, 0.22, 0.3)
	opp_row.add_child(_portrait)
	var opp_col := VBoxContainer.new()
	opp_row.add_child(opp_col)
	_opp_name = Label.new()
	_opp_name.add_theme_font_size_override("font_size", 22)
	opp_col.add_child(_opp_name)
	_opp_taunt = Label.new()
	_opp_taunt.add_theme_font_size_override("font_size", 16)
	_opp_taunt.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))
	_opp_taunt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	opp_col.add_child(_opp_taunt)

	_score = Label.new()
	_score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_score.add_theme_font_size_override("font_size", 22)
	vbox.add_child(_score)
	_round = Label.new()
	_round.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_round.add_theme_font_size_override("font_size", 18)
	_round.add_theme_color_override("font_color", Color(0.75, 0.75, 0.85))
	vbox.add_child(_round)

	_dice_row = HBoxContainer.new()
	_dice_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_dice_row.add_theme_constant_override("separation", 10)
	vbox.add_child(_dice_row)
	for i in 5:
		var f := DieFace.new()
		_dice_row.add_child(f)
		_dice_faces.append(f)

	_msg = Label.new()
	_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_msg.add_theme_font_size_override("font_size", 18)
	_msg.add_theme_color_override("font_color", Color(0.92, 0.88, 0.75))
	_msg.custom_minimum_size = Vector2(600, 70)
	vbox.add_child(_msg)

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 12)
	vbox.add_child(btn_row)
	_btn_roll = _make_button("ROLL", btn_row, _on_roll)
	_btn_bank = _make_button("BANK", btn_row, _on_bank)
	_btn_push = _make_button("PUSH", btn_row, _on_push)
	_btn_leave = _make_button("LEAVE", btn_row, _on_leave)

	_hint = Label.new()
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_font_size_override("font_size", 15)
	_hint.add_theme_color_override("font_color", Color(0.55, 0.55, 0.62))
	_hint.text = "Space/A: roll   X/pad-X: bank   Esc/pad-B: push / leave"
	vbox.add_child(_hint)


func _make_button(text: String, parent: Control, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 20)
	b.custom_minimum_size = Vector2(120, 44)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func is_open() -> bool:
	return _open


func open_table() -> void:
	_open = true
	_mode = "select"
	_game = null
	_refresh_tables()
	_refresh()
	visible = true


func close_table() -> void:
	_open = false
	visible = false
	closed.emit()


func _refresh_tables() -> void:
	for c in _table_row.get_children():
		c.queue_free()
	_table_buttons.clear()
	for tid in DiceGame.table_ids():
		var b := Button.new()
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 18)
		var unlocked: bool = DiceGame.table_unlocked(game_state, tid)
		b.text = DiceGame.table_name(tid) if unlocked else "??? (locked)"
		b.disabled = not unlocked
		b.button_pressed = (tid == _table and unlocked)
		if not unlocked:
			b.tooltip_text = DiceGame.lock_reason(game_state, tid)
		var id: String = tid
		b.pressed.connect(_on_table.bind(id))
		_table_row.add_child(b)
		_table_buttons[tid] = b


func _on_table(tid: String) -> void:
	if not DiceGame.table_unlocked(game_state, tid):
		return
	_table = tid
	_start_game()


func _opponent_for(tid: String) -> Dictionary:
	if tid == "copper":
		return {"name": DiceGame.WRATH_NAME, "ai_bank": 800, "taunt": "[WIRING] Wrath: \"Roll. I'll wait. I always wait.\""}
	if tid == "quiet":
		return {"name": DiceGame.LATCH_NAME, "ai_bank": 1200, "taunt": "[WIRING] Latch: \"One question. Win it.\""}
	var o: Dictionary = DiceGame.blend_opponent(game_state)
	return {"name": str(o.get("name", "Regular")), "ai_bank": int(o.get("ai_bank", 1000)),
		"taunt": str(o.get("taunt", "")), "loss_line": str(o.get("loss_line", ""))}


## Story-beat paging (Wrath intro on first copper sit). Same flip-beat
## pattern: input advances the beat; finishing resumes what was queued.
func _play_beat(lines: Array, resume: String) -> void:
	_beat_lines = lines
	_beat_page = 0
	_beat_resume = resume
	_mode = "beat"
	_set_actions(false, false, false)
	_show_beat_line()


func _show_beat_line() -> void:
	if _beat_page >= _beat_lines.size():
		_beat_lines = []
		if _beat_resume == "game":
			_beat_resume = ""
			_launch_game()
		elif _beat_resume == "close":
			_beat_resume = ""
			close_table()
		return
	var e: Dictionary = _beat_lines[_beat_page]
	var c := str(e.get("character", ""))
	var t := str(e.get("text", ""))
	_msg.text = (c + ": " + t) if c != "" else t
	_beat_page += 1


func _start_game() -> void:
	if not DiceGame.pay_buy_in(game_state, _table):
		_msg.text = DiceGame.flow_line("buyin_denied")
		_refresh()
		return
	if _table == "copper" and DiceGame.one_shot(game_state, "wrath_intro"):
		# First copper sit: Wrath's intro scene, then Murray's sit hint.
		DiceGame.one_shot(game_state, "murray_sit")
		_pending_sit = str(DiceGame.MURRAY_HINTS.get("sit", ""))
		_play_beat(DiceGame.WRATH_INTRO_LINES, "game")
		return
	_launch_game()


func _launch_game() -> void:
	var opp: Dictionary = _opponent_for(_table)
	_opp = opp
	_game = DiceGame.new()
	_game.setup(_table, str(opp["name"]))
	_game.ai_bank = int(opp["ai_bank"])
	_mode = "playing"
	_opp_taunt.text = str(opp["taunt"])
	_msg.text = "[WIRING] %s deals. First to %d." % [str(opp["name"]), DiceGame.WIN_SCORE]
	if _pending_sit != "":
		_msg.text += "\n" + _pending_sit
		_pending_sit = ""
	_refresh()


func _refresh() -> void:
	if _mode == "beat":
		return  # beat paging owns _msg; don't clobber it
	if _game == null or _mode == "select":
		_title.text = "DEAD MAN'S DICE"
		_opp_name.text = "Pick your table."
		_score.text = ""
		_round.text = ""
		for f in _dice_faces:
			f.value = 1
			f.dimmed = true
			f.queue_redraw()
		_set_actions(false, false, false)
		return
	_title.text = "DEAD MAN'S DICE — " + DiceGame.table_name(_table).to_upper()
	_opp_name.text = _game.opponent_name
	_score.text = "You %d  —  %s %d   (first to %d)" % [_game.player_banked, _game.opponent_name, _game.opp_banked, DiceGame.WIN_SCORE]
	_round.text = "Round score: %d" % _game.round_score
	for i in _dice_faces.size():
		var f: Control = _dice_faces[i]
		if i < _game.last_roll.size():
			f.value = int(_game.last_roll[i])
			f.dimmed = false
		else:
			f.value = 1
			f.dimmed = true
		f.queue_redraw()
	if _mode == "playing":
		_set_actions(true, not _game.last_roll.is_empty(), not _game.last_roll.is_empty())
	elif _mode == "over":
		_set_actions(false, false, false)


func _set_actions(roll: bool, bank: bool, push: bool) -> void:
	_btn_roll.disabled = not roll
	_btn_bank.disabled = not bank
	_btn_push.disabled = not push
	_btn_leave.disabled = false


func _on_roll() -> void:
	if _mode != "playing" or _game == null or _game.phase != "player_turn":
		return
	if not _game.last_roll.is_empty():
		return  # must bank or push first
	var r: Dictionary = _game.player_roll()
	if bool(r["bust"]):
		_msg.text = DiceGame.flow_line("bust_line")
		if DiceGame.one_shot(game_state, "murray_bust"):
			_msg.text += "\n" + str(DiceGame.MURRAY_HINTS.get("bust", ""))
		_refresh()
		_opponent_turn.call_deferred()
	else:
		_msg.text = "You roll %d. Push, or bank at %d?" % [int(r["score"]), int(r["score"])]
		_refresh()


func _on_bank() -> void:
	if _mode != "playing" or _game == null or _game.last_roll.is_empty():
		return
	var banked: int = _game.round_score
	var res: Dictionary = _game.player_bank()
	_game.last_roll = []
	if str(res["winner"]) == "player":
		_finish(true)
		return
	_msg.text = "Banked at %d. %s to roll." % [banked, _game.opponent_name]
	_refresh()
	_opponent_turn.call_deferred()


func _on_push() -> void:
	if _mode != "playing" or _game == null or _game.last_roll.is_empty():
		return
	_game.last_roll = []
	_msg.text = "[WIRING] Pushing with %d dice..." % _game.dice_in_hand
	if DiceGame.one_shot(game_state, "murray_push"):
		_msg.text += "\n" + str(DiceGame.MURRAY_HINTS.get("push", ""))
	_refresh()


func _opponent_turn() -> void:
	if _game == null or _mode != "playing":
		return
	_set_actions(false, false, false)
	var res: Dictionary = _game.play_opponent_turn()
	var log: Array = res["log"]
	for entry in log:
		var dice: Array = entry["dice"]
		_game.last_roll = dice
		_refresh()
		_msg.text = "%s rolls %d..." % [_game.opponent_name, int(entry["score"])]
		await get_tree().create_timer(0.45).timeout
		if _mode != "playing":
			return
	_game.last_roll = []
	var o_banked := 0
	for entry in log:
		o_banked += int(entry["score"])
	if bool(res["bust"]):
		_msg.text = DiceGame.flow_line("opp_bust") % _game.opponent_name
	else:
		_msg.text = "%s banks at %d. Your turn." % [_game.opponent_name, o_banked]
	if str(res["winner"]) == "opponent":
		_finish(false)
		return
	_game.phase = "player_turn"
	_refresh()


func _finish(player_won: bool) -> void:
	_mode = "over"
	_refresh()
	if player_won:
		var res: Dictionary = DiceGame.record_win(game_state, _table)
		if _table == "copper":
			_msg.text = "You take the pot — %d soul credits." % DiceGame.COPPER_POT
		elif _table == "blend":
			_msg.text = "[WIRING] You take the pot: a house blend. Smoke it wisely."
			var ll := str(_opp.get("loss_line", ""))
			if ll != "":
				_msg.text += "\n" + ll
		else:
			var ans: Dictionary = res.get("answer", {})
			if not ans.is_empty():
				_msg.text = "[WIRING] Latch answers: \"%s\"" % str(ans.get("answer", ""))
			else:
				_msg.text = "[WIRING] Latch nods. No more answers left in them."
		if bool(res.get("wrath_flip", false)):
			_flip_page = 0
			_show_flip()
	else:
		DiceGame.record_loss(game_state, _table)
		_msg.text = "%s takes the pot." % _game.opponent_name
	_refresh()
	_msg.text += "\n[WIRING] ROLL to play again, or LEAVE."


func _show_flip() -> void:
	var lines: Array = DiceGame.WRATH_FLIP_LINES
	if _flip_page < lines.size():
		var e: Dictionary = lines[_flip_page]
		var c := str(e.get("character", ""))
		var t := str(e.get("text", ""))
		_msg.text = (c + ": " + t) if c != "" else t
		_flip_page += 1


func _on_leave() -> void:
	if _mode == "beat":
		_show_beat_line()
		return
	if _mode == "over" and _flip_page > 0 and _flip_page < DiceGame.WRATH_FLIP_LINES.size():
		_show_flip()  # paging through the table-flip beat
		return
	close_table()


func _unhandled_input(event: InputEvent) -> void:
	if not _open or not visible:
		return
	if _mode == "beat":
		get_viewport().set_input_as_handled()
		_show_beat_line()
		return
	if event.is_action_pressed("ui_accept"):
		get_viewport().set_input_as_handled()
		if _mode == "select":
			_on_table(_table)
		elif _mode == "playing":
			_on_roll()
		elif _mode == "over":
			_on_table(_table)
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_X:
			get_viewport().set_input_as_handled()
			_on_bank()
			return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		if _mode == "playing":
			_on_push()
		else:
			_on_leave()
		return
	if event is InputEventJoypadButton and event.pressed:
		var b := (event as InputEventJoypadButton).button_index
		if b == 0:  # A: roll
			get_viewport().set_input_as_handled()
			_on_roll()
		elif b == 2:  # X: bank
			get_viewport().set_input_as_handled()
			_on_bank()
		elif b == 1:  # B: push / leave
			get_viewport().set_input_as_handled()
			if _mode == "playing":
				_on_push()
			else:
				_on_leave()
