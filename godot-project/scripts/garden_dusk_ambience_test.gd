extends SceneTree
## Lightweight deterministic Reserve ambience regression tests, with no LFS.
## Godot 4.3 --headless --path godot-project --script res://scripts/garden_dusk_ambience_test.gd

const Atmosphere := preload("res://scripts/garden_dusk_ambience.gd")
const Clock := preload("res://scripts/reserve_clock.gd")

var _checks: int = 0
var _failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_check(is_equal_approx(Atmosphere.glow_for_minutes(540.0), 0.12),
		"daytime lanterns remain subtle")
	_check(is_equal_approx(Atmosphere.glow_for_minutes(60.0), 1.0),
		"nighttime lanterns are warm and visible")
	_check(is_equal_approx(Atmosphere.glow_for_minutes(1380.0), 1.0),
		"night glow wraps midnight correctly")
	_check(Atmosphere.glow_for_minutes(1110.0) > Atmosphere.glow_for_minutes(1020.0),
		"glow ramps up during dusk")
	_check(is_equal_approx(Atmosphere.glow_for_minutes(1170.0), 1.0),
		"lanterns reach night glow exactly at the shared phase boundary")
	_check(Clock.light_for(1170.0).is_equal_approx(Clock.NIGHT_LIGHT),
		"world tint reaches night color at the same boundary")
	_check(Atmosphere.glow_for_minutes(360.0) < Atmosphere.glow_for_minutes(300.0),
		"glow fades during dawn")
	_check(is_equal_approx(Atmosphere.glow_for_minutes(360.0),
		Atmosphere.glow_for_minutes(1800.0)), "day-index independent lighting")
	_check(Atmosphere.mote_opacity(1100.0) > Atmosphere.mote_opacity(700.0),
		"fireflies appear more strongly toward evening")
	var specimen := {
		"home": Vector2(100.0, 200.0), "phase": 1.34,
		"speed": 0.6, "drift_x": 13.0, "drift_y": 8.0
	}
	var sample_a := Atmosphere.sample_mote(specimen, 9.8)
	var sample_b := Atmosphere.sample_mote(specimen, 9.8)
	_check(sample_a == sample_b, "mote paths are deterministic")
	for i in range(300):
		var t := float(i) * 0.08
		var p := Atmosphere.sample_mote(specimen, t)
		var next := Atmosphere.sample_mote(specimen, t + 0.016)
		_check(absf(p.x - 100.0) <= 13.001 and absf(p.y - 200.0) <= 8.001,
			"mote drift is locally bounded")
		_check(p.distance_to(next) < 0.5, "motes move smoothly at frame boundaries")

	var room := Node2D.new()
	room.name = "OutdoorAtmosphereTest"
	root.add_child(room)
	var clock = Clock.new()
	clock.name = "ReserveClock"
	clock.show_clock = false
	clock.apply_world_tint = false
	room.add_child(clock)
	clock.set_total_minutes(540.0)
	var ambience = Atmosphere.new()
	ambience.name = "GardenDuskAmbience"
	ambience.bounds = Rect2(-640, -360, 1280, 720)
	ambience.mote_count = 18
	ambience.seed_value = 319
	ambience.lantern_positions = PackedVector2Array([
		Vector2(-300, 100), Vector2(0, 30), Vector2(350, 140)])
	room.add_child(ambience)
	_check(ambience.get_mote_count() == 18, "motes generated exactly once")
	_check(ambience.get_lantern_count() == 3, "three lanterns emit warm light")
	var light := ambience.get_node_or_null("ReserveLanternLight0") as PointLight2D
	_check(light != null and light.texture != null, "lantern uses a procedural radial glow")
	_check(ambience.get_node_or_null("CollisionShape2D") == null,
		"atmosphere never creates terrain collision")
	_check(ambience.z_index < 0, "atmosphere draws beneath NPCs and canopy")
	if light != null:
		var day_energy := light.energy
		clock.set_total_minutes(1260.0)
		ambience._process(0.05)
		_check(light.energy > day_energy * 2.0, "night brightness follows ReserveClock")
		clock.set_total_minutes(1110.0)
		ambience._process(0.05)
		_check(light.energy > day_energy, "dusk light increases from daytime")
		clock.set_total_minutes(360.0)
		ambience._process(0.05)
		_check(light.energy < day_energy * 6.0, "dawn light fades from night")
	_check(ambience.get_mote_count() == 18 and ambience.get_lantern_count() == 3,
		"clock changes do not allocate new motes or lights")
	room.queue_free()

	if _failures == 0:
		print("[GARDEN ATMOSPHERE] PASS %d checks" % _checks)
	else:
		push_error("[GARDEN ATMOSPHERE] FAIL %d/%d" % [_failures, _checks])
	quit(1 if _failures > 0 else 0)

func _check(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("[GARDEN ATMOSPHERE] " + description)
