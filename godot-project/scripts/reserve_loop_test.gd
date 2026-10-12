extends SceneTree
## Deterministic Reserve clock and interaction tests. No LFS art needed.
## godot --headless --path godot-project --script res://scripts/reserve_loop_test.gd

const Clock := preload("res://scripts/reserve_clock.gd")
const Guide := preload("res://scripts/reserve_guide.gd")
const Resident := preload("res://scripts/reserve_creature.gd")
const Loader := preload("res://scripts/critical_sprite_loader.gd")
const TitleScreen := preload("res://scripts/title_screen.gd")

var _failed := 0
var _checks := 0
var _dusk_days: Array[int] = []
var _navigated_to: String = ""

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	# Bundled images must decode without Git LFS smudge.
	for spec in [
		["dragonthorn", 1600, 1600], ["gloomcap", 1120, 2240],
		["spinehopper", 1120, 2240], ["bellmaw", 384, 384],
		["wispwillow", 384, 384]]:
		var path: String = "res://assets/creatures/" + spec[0] + ".png"
		# Bypass the original PNG deliberately: CI's lfs:true checkout
		# would otherwise conceal broken bundled fallback filenames.
		var backup := Loader._load_bundled(path)
		_check(backup != null, path + " exact fallback must decode without LFS")
		var texture := Loader.load_texture(path)
		_check(texture != null, path + " must decode with or without LFS")
		if texture != null:
			_check(texture.get_width() == int(spec[1]) and
				texture.get_height() == int(spec[2]),
				path + " matches approved Drive artwork size")

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
	# Time-skip over two dusks should emit two distinct day numbers.
	_dusk_days.clear()
	c.set_total_minutes(1000.0)
	c.advance_seconds(1440.0)
	_check(_dusk_days.size() == 2 and _dusk_days[0] == 1 and _dusk_days[1] == 2,
		"large time skip emits each dusk once")
	c.queue_free()

	# The title-screen QA shortcut should reach the scene from an Android
	# debug build without changing the standard NEW GAME progression.
	var original_dev_setting: Variant = ProjectSettings.get_setting("reaper/dev_shortcuts", false)
	ProjectSettings.set_setting("reaper/dev_shortcuts", true)
	var title = TitleScreen.new()
	title.scene_changer = Callable(self, "_capture_scene")
	title._enter_reserve_test()
	_check(_navigated_to == "res://scenes/room_gd1.tscn",
		"debug title-screen shortcut opens Reserve immediately")
	title.free()
	ProjectSettings.set_setting("reaper/dev_shortcuts", original_dev_setting)

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
	_check(residents.get_node_or_null("ObservedSoulThread") != null,
		"interaction generates a visible soul-thread response")
	_check(guide._resident_count() == 2,
		"VFX and sensor nodes are not counted as living residents")
	_check(guide.is_observing_resident(), "guide advertises nearby observation focus")
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

func _capture_scene(path: String) -> void:
	_navigated_to = path


func _record_dusk(day: int) -> void:
	_dusk_days.append(day)

func _check(ok: bool, description: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
		push_error("[RESERVE LOOP TEST] " + description)
