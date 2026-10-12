extends SceneTree
## Deterministic Reserve clock and interaction tests. No LFS art needed.
## godot --headless --path godot-project --script res://scripts/reserve_loop_test.gd

const Clock := preload("res://scripts/reserve_clock.gd")
const Guide := preload("res://scripts/reserve_guide.gd")
const Resident := preload("res://scripts/reserve_creature.gd")

var _failed := 0
var _checks := 0
var _dusk_days: Array[int] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_check(Clock.phase_for(0.0) == "night", "midnight is night")
	_check(Clock.phase_for(360.0) == "dawn", "06:00 is dawn")
	_check(Clock.phase_for(540.0) == "day", "09:00 is day")
	_check(Clock.phase_for(1079.0) == "dusk", "17:59 is dusk")
	_check(Clock.phase_for(1260.0) == "night", "21:00 is night")
	_check(Clock.light_for(540.0).r > Clock.light_for(0.0).r,
		"daylight is brighter than midnight")
	_check(Clock.phase_for(1440.0 + 540.0) == "day",
		"time wraps across consecutive game days")
	var c = Clock.new()
	c.show_clock = false
	c.cycle_seconds = 720.0
	root.add_child(c)
	c.dusk_started.connect(_record_dusk)
	c.set_total_minutes(1018.0)
	c.advance_seconds(2.0) # 4 game minutes; crosses 17:00.
	_check(_dusk_days.size() == 1 and _dusk_days[0] == 1,
		"dusk signal fires once when crossing 17:00")
	c.advance_seconds(2.0)
	_check(_dusk_days.size() == 1, "dusk signal does not repeat")
	_check(c.get_phase() == "dusk", "clock phase changes at dusk")
	_check(c.get_total_minutes() > 1020.0, "clock continues advancing")
	c.queue_free()

	var room := Node2D.new()
	room.name = "ReserveTestRoom"
	root.add_child(room)
	var player := CharacterBody2D.new()
	player.name = "Player"
	player.add_to_group("player")
	room.add_child(player)
	var residents := Node2D.new()
	residents.name = "Creatures"
	room.add_child(residents)
	var near = Resident.new()
	near.name = "Dragonthorn"
	near.position = Vector2(50, 0)
	residents.add_child(near)
	var far = Resident.new()
	far.name = "Gloomcap"
	far.position = Vector2(115, 0)
	residents.add_child(far)
	near._on_body_entered(player)
	far._on_body_entered(player)
	var guide = Guide.new()
	guide.name = "ReserveGuide"
	room.add_child(guide)
	guide._select_nearest()
	_check(guide.get("_selected") == near,
		"nearest aware creature exclusively receives focus")
	_check(near.get("_selected") and not far.get("_selected"),
		"other creature prompt stays hidden")
	_check(bool(near.trigger_interaction()), "focused creature can be observed")
	_check(float(near.get("_reaction_time")) > 0.0,
		"interaction triggers a visible reaction")
	near._on_body_exited(player)
	guide._select_nearest()
	_check(guide.get("_selected") == far,
		"focus moves when first creature leaves range")
	far._on_body_exited(player)
	guide._select_nearest()
	_check(guide.get("_selected") == null, "focus clears outside all ranges")
	room.queue_free()

	if _failed == 0:
		print("[RESERVE LOOP TEST] PASS %d checks" % _checks)
	else:
		push_error("[RESERVE LOOP TEST] FAIL %d/%d" % [_failed, _checks])
	quit(1 if _failed > 0 else 0)

func _record_dusk(day: int) -> void:
	_dusk_days.append(day)

func _check(ok: bool, description: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
		push_error("[RESERVE LOOP TEST] " + description)
