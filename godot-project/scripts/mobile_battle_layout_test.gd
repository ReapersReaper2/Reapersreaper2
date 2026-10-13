extends SceneTree
## Regressions from 2026-10-13 on-device recording:
## text must never become a one-character-wide vertical column; combat
## action buttons must stay within the 1280x720 Android canvas.
const Battle := preload("res://scripts/battle.gd")
var checks: int = 0
var failed: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var size := Vector2(1280, 720)
	var layout: Dictionary = Battle.battle_layout(size)
	var narrative: Rect2 = layout["message"]
	var commands: Rect2 = layout["commands"]
	check(narrative.size.x >= 720.0,
		"battle narrative has usable width instead of 1-character columns")
	check(narrative.size.y >= 160.0 and narrative.end.y <= size.y,
		"battle narrative stays fully within the phone viewport")
	check(commands.position.x >= narrative.end.x + 20.0,
		"command grid never covers battle dialogue")
	check(commands.end.x <= size.x and commands.end.y <= size.y,
		"all command buttons remain inside the viewport")

	var battle = Battle.new()
	battle.fast_mode = true
	battle.battle_config = {
		"player_creature_id": "snapling",
		"player_level": 5,
		"enemy_creature_id": "bellowscap",
		"enemy_level": 2,
		"return_room": "p1",
		"return_pos": Vector2.ZERO,
	}
	root.add_child(battle)
	await process_frame
	await process_frame
	var bg: ColorRect = battle.get_node("BattleBackground")
	var hud: Control = battle.get_node("BattleHUD")
	var panel: PanelContainer = battle.get_node("BattleHUD/BattleMessagePanel")
	var menu: GridContainer = battle.get_node("BattleHUD/BattleCommands")
	check(bg.size.is_equal_approx(size),
		"fullscreen background genuinely covers Node2D-hosted battle viewport")
	check(hud.size.is_equal_approx(size),
		"battle modal has a sized UI parent for its controls")
	check(panel.position.is_equal_approx(narrative.position) and
		panel.size.is_equal_approx(narrative.size),
		"narrative panel keeps the tested full-width bounds")
	check(battle._msg.get_global_rect().size.x > 650.0,
		"actual message label wraps horizontally, never vertically")
	check(menu.columns == 2 and menu.get_child_count() == 5,
		"five commands laid out as accessible 2-column touch grid")
	check(menu.position.is_equal_approx(commands.position),
		"commands occupy their dedicated right-side lane")
	print("[MOBILE BATTLE DIAGNOSTIC] commands=", commands, " menu=", menu.get_global_rect(), " children=", menu.get_child_count())
	for button in menu.get_children():
		if button is Button:
			var rect := (button as Button).get_global_rect()
			print("[MOBILE BATTLE DIAGNOSTIC] button=", button.text, " rect=", rect)
			check(rect.end.x <= size.x and rect.end.y <= size.y,
				"command touch target not clipped beyond physical canvas")
	check(not bg.mouse_filter == Control.MOUSE_FILTER_STOP,
		"background visual does not intercept command touches")

	battle.queue_free()
	if failed == 0:
		print("[MOBILE BATTLE LAYOUT] PASS %d checks" % checks)
	else:
		push_error("[MOBILE BATTLE LAYOUT] FAIL %d/%d" % [failed, checks])
	quit(1 if failed > 0 else 0)

func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failed += 1
		push_error("[MOBILE BATTLE LAYOUT] " + description)
