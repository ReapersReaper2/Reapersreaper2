extends SceneTree
## User device video regression: dialogue must fit BETWEEN the mobile
## joystick on the left and USE/SWORD controls on the right.
const Dialogue := preload("res://scenes/dialogue_box.tscn")
const MobileHUD := preload("res://scripts/mobile_touch_overlay.gd")

var failed: int = 0
var checks: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var viewport_size := Vector2(1280, 720)
	var bounds: Rect2 = DialogueBox.mobile_dialogue_rect(viewport_size)
	var hud = MobileHUD.new()
	hud.size = viewport_size
	root.add_child(hud)
	var left_limit: float = hud._joy_center().x + hud._radius() + 12.0
	var right_limit: float = hud._interact_center().x - hud._button_radius() - 12.0
	check(bounds.position.x >= left_limit,
		"chat box starts after visible joystick ring")
	check(bounds.end.x <= right_limit,
		"chat box ends before USE button and does not cover SWORD")
	check(bounds.position.y > viewport_size.y * 0.68 and bounds.end.y < viewport_size.y,
		"chat remains low in the viewport without clipping")
	check(bounds.size.x >= 680.0 and bounds.size.y >= 155.0,
		"dialogue remains readable with ample width and height")

	var dialogue = Dialogue.instantiate()
	dialogue.force_mobile_layout = true
	root.add_child(dialogue)
	await process_frame
	var panel: PanelContainer = dialogue.get_node("Panel")
	check(panel.position.is_equal_approx(bounds.position),
		"actual modal panel uses tested clear-center location")
	check(panel.size.is_equal_approx(bounds.size),
		"actual modal panel is sized explicitly, not collapsing to zero")
	var text_label: RichTextLabel = dialogue.get_node("Panel/Margin/VBox/HBox/TextLabel")
	check(text_label.get_theme_font_size("normal_font_size") >= 24,
		"real mobile body text enlarged for landscape phone")
	check(dialogue.start_dialogue([
		{"type":"dialogue", "character":"LUNA",
		"text":"The far shore. Everybody wakes up here eventually."}]),
		"dialogue can still start with unchanged story text")
	check(dialogue.is_active(), "dialogue keeps gameplay modal semantics")
	dialogue.advance()
	dialogue.advance()
	check(not dialogue.is_active(), "USE/SWORD dialogue advance still works")

	var wide := DialogueBox.mobile_dialogue_rect(Vector2(1600, 900))
	check(wide.position.x >= 290.0 and wide.end.x <= 1230.0,
		"layout scales conservatively on high resolution 16:9 screens")
	root.remove_child(dialogue)
	dialogue.free()
	hud.queue_free()
	if failed == 0:
		print("[MOBILE DIALOGUE LAYOUT] PASS %d checks" % checks)
	else:
		push_error("[MOBILE DIALOGUE LAYOUT] FAIL %d/%d" % [failed, checks])
	quit(1 if failed > 0 else 0)

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failed += 1
		push_error("[MOBILE DIALOGUE LAYOUT] " + label)
