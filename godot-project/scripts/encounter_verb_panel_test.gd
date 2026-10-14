extends SceneTree
## Visually safe touch layout for ENCOUNTER-IMPL §1.6.
## No inventory mutation or capture math can be triggered in this widget.
const VerbPanel := preload("res://scripts/encounter_verb_panel.gd")
const TouchHUD := preload("res://scripts/mobile_touch_overlay.gd")
var checks := 0
var failed := 0
var choices: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failed += 1
		push_error("[ENCOUNTER VERBS] " + description)

func _chosen(verb: String) -> void:
	choices.append(verb)

func _run() -> void:
	var logical := Vector2(1280, 720)
	var bounds := VerbPanel.mobile_verb_rect(logical)
	_check(bounds.position.x >= 230 and bounds.end.x <= 990,
		"panel occupies central lane between left joystick and right USE/SWORD")
	_check(bounds.end.y < 720 and bounds.position.y > 520,
		"panel stays low without falling off Android viewport")
	_check(VerbPanel.allowed_verbs(false) == ["Offer", "Tend", "Withdraw"],
		"asking shows only three locked verbs by default")
	_check(VerbPanel.allowed_verbs(true) == ["Offer", "Tend", "Withdraw", "Guide"],
		"Guide is conditional fourth verb, not always exposed")
	_check(VerbPanel.button_target_width(logical, 4) >= 160,
		"four thumb-sized buttons fit horizontally inside 744px lane")
	var narrow := VerbPanel.mobile_verb_rect(Vector2(960, 540))
	_check(narrow.position.x >= 175 and narrow.end.x <= 740 and narrow.end.y < 540,
		"same proportions remain clear on lower resolution landscape")
	var wide := VerbPanel.mobile_verb_rect(Vector2(1600, 900))
	_check(wide.position.x >= 290 and wide.end.x <= 1240,
		"high-resolution widescreen keeps input margins")

	var hud = TouchHUD.new()
	hud.size = logical
	root.add_child(hud)
	var joystick_limit: float = hud._joy_center().x + hud._radius()
	var interact_limit: float = hud._interact_center().x - hud._button_radius()
	_check(bounds.position.x > joystick_limit and bounds.end.x < interact_limit,
		"panel doesn't overlap actual mobile joystick or USE circle")

	var panel = VerbPanel.new()
	panel.verb_chosen.connect(_chosen)
	root.add_child(panel)
	await process_frame
	_check(not panel.visible and not panel.is_open(),
		"modal remains hidden until director deliberately opens it")
	panel.open_for("Dragonthorn", false)
	await process_frame
	var frame: PanelContainer = panel.get_node("AskingFrame")
	var options: HBoxContainer = panel.get_node("AskingFrame/Body/Verbs")
	var actual := frame.get_global_rect()
	var wanted := VerbPanel.mobile_verb_rect(root.get_visible_rect().size)
	_check(frame.visible and panel.is_open() and panel.has_verb("Offer") and
		not panel.has_verb("Guide"),
		"opening creates exactly permitted three-verb asking")
	_check(actual.position.is_equal_approx(wanted.position) and
		actual.size.is_equal_approx(wanted.size),
		"actual frame matches safe viewport rectangle")
	_check(options.get_child_count() == 3,
		"three verbs are actual GUI Buttons, not drawn inert text")
	for child in options.get_children():
		if child is Button:
			var rect := (child as Button).get_global_rect()
			_check(rect.position.x >= wanted.position.x and
				rect.end.x <= wanted.end.x and rect.end.y <= wanted.end.y,
				"each 3-verb touch hitbox stays inside frame")
			_check(rect.size.y >= 55,
				"mobile verb target is tall enough for a finger")

	(panel._controls["Tend"] as Button).pressed.emit()
	_check(choices.size() == 1 and choices[0] == "Tend",
		"pressing Tend emits a verb request rather than awarding warmth")
	var stale_offer: Button = panel._controls["Offer"]
	panel.open_for("Gloomcap", true)
	stale_offer.pressed.emit()
	_check(choices.size() == 1,
		"queued touch from old creature cannot select fruit for new creature")
	await process_frame
	options = panel.get_node("AskingFrame/Body/Verbs")
	_check(options.get_child_count() == 4 and panel.has_verb("Guide"),
		"Guide button only appears with explicitly eligible Lullmother")
	for child in options.get_children():
		if child is Button:
			var rect := (child as Button).get_global_rect()
			_check(rect.position.x >= wanted.position.x and
				rect.end.x <= wanted.end.x and rect.end.y <= wanted.end.y,
				"four-verb button fits actual mobile viewport")
	(panel._controls["Guide"] as Button).pressed.emit()
	_check(choices.size() == 2 and choices[1] == "Guide",
		"conditional Guide emits its action request")
	panel.dismiss()
	_check(not panel.visible and not panel.is_open(),
		"pause/withdraw/room change can fully dismiss encounter UI")
	(panel._controls["Guide"] as Button).pressed.emit()
	_check(choices.size() == 2,
		"stale finger-up event can't call Guide after panel dismissal")
	hud.queue_free()
	panel.queue_free()
	if failed == 0:
		print("[ENCOUNTER VERBS] PASS %d checks" % checks)
	else:
		push_error("[ENCOUNTER VERBS] FAIL %d/%d" % [failed, checks])
	quit(1 if failed > 0 else 0)
