extends SceneTree
## Bellhollow battlefield presentation regression: smoke, embers and
## ground-tethered footstep ash. No Git LFS assets required.
## godot --headless --path godot-project --script res://scripts/prologue_bridge_atmosphere_test.gd

const Atmosphere := preload("res://scripts/prologue_bridge_atmosphere.gd")
const RoomP1 := preload("res://scenes/room_p1.tscn")

var _checks := 0
var _failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var times := [0.0, 0.3, 7.8, 32.0, 130.0]
	for t in times:
		for phase in [0.0, 0.77, 2.1, 5.3]:
			var sp: Vector2 = Atmosphere.smoke_offset(t, phase, 0.4)
			var ep: Vector2 = Atmosphere.ash_offset(t, phase, 0.65)
			_check(sp == Atmosphere.smoke_offset(t, phase, 0.4) and
				ep == Atmosphere.ash_offset(t, phase, 0.65),
				"smoke and ash positions are deterministic across reloads")
			_check(absf(sp.x) <= 27.001 and absf(sp.y) <= 12.001,
				"background smoke cannot fly across gameplay corridor")
			_check(absf(ep.x) <= 18.001 and absf(ep.y) <= 18.001,
				"cinders stay within their original drifting area")
			_check(sp.distance_to(Atmosphere.smoke_offset(t + 0.016, phase, 0.4)) < 0.25,
				"smoke shifts smoothly between 60fps frames")
			_check(ep.distance_to(Atmosphere.ash_offset(t + 0.016, phase, 0.65)) < 0.35,
				"ash drifts smoothly without wrapping or teleporting")

	_check(is_equal_approx(Atmosphere.footprint_opacity(0.0), 1.0),
		"fresh footstep dust becomes visible")
	_check(Atmosphere.footprint_opacity(0.36) > 0.0 and
		Atmosphere.footprint_opacity(0.36) < 1.0,
		"old dust visibly fades")
	_check(is_zero_approx(Atmosphere.footprint_opacity(1.0)),
		"footstep dust disappears after its short lifetime")

	# P1 retains the mortal layout and collision; visual effects are a
	# sibling of the bridge, not a separate playable obstacle.
	var p1 = RoomP1.instantiate()
	var bridge := p1.get_node_or_null("WalkableBridge")
	var atmosphere := p1.get_node_or_null("BattlefieldAtmosphere")
	_check(bridge != null and atmosphere != null,
		"approved stone bridge and atmospheric pass both exist")
	_check(atmosphere != null and atmosphere.get_script() == Atmosphere,
		"Bellhollow scene is linked to the atmospheric renderer")
	if atmosphere != null:
		_check(atmosphere.get_index() > bridge.get_index() and
			atmosphere.get_index() < p1.get_node("Player").get_index(),
			"smoke draws over stone but below Mollosar and Mira")
		_check(atmosphere.z_index == -1 and not atmosphere.z_as_relative,
			"effects cannot cover HUD and dialogue canvases")
		_check(atmosphere.get_child_count() == 0,
			"visual atmosphere does not add colliders or touch blockers")
	_check(p1.get_node_or_null("BridgeRails") != null and
		p1.get_node_or_null("TutorialTrigger") != null and
		p1.get_node_or_null("WaveSpawner") != null,
		"existing sword tutorial, invaders and bridge collisions remain intact")
	_check(p1.get_node_or_null("Mira") != null and
		p1.get_node_or_null("WoundedSoldier") != null and
		p1.get_node_or_null("Luna") == null,
		"mortal story characters stay in correct opening scene")
	p1.free()

	# Standalone room: motion emits step dust on its own, without modifying
	# the player actor. Teleports and idle standing cannot leave trails.
	var fixture := Node2D.new()
	root.add_child(fixture)
	var player := Node2D.new()
	player.name = "Player"
	fixture.add_child(player)
	var fx = Atmosphere.new()
	fx.name = "BattlefieldAtmosphere"
	fixture.add_child(fx)
	_check(fx.get_smoke_count() == 12 and fx.get_ash_count() == 36,
		"deterministic smoke and ash counts stay bounded on Android")
	_check(fx.get_child_count() == 0 and fx.get_footprint_count() == 0,
		"effects begin without allocating sprites or collision shapes")
	fx._process(0.05)
	for i in range(10):
		player.position += Vector2(18.0, 0.0)
		fx._process(0.05)
	_check(fx.get_footprint_count() >= 2 and fx.get_footprint_count() <= 3,
		"walking the bridge produces subtle periodic ash footprints")
	var before_teleport: int = fx.get_footprint_count()
	player.position += Vector2(220, 0)
	fx._process(0.02)
	_check(fx.get_footprint_count() == before_teleport,
		"cutscenes/teleports never spawn long footprint streaks")
	fx._process(0.75)
	_check(fx.get_footprint_count() == 0,
		"all footstep effects release themselves without persistent nodes")
	_check(fx.get_smoke_count() == 12 and fx.get_ash_count() == 36,
		"running effects never allocates more smoke/ash particles")
	fixture.queue_free()

	if _failures == 0:
		print("[BELLHOLLOW ATMOSPHERE] PASS %d checks" % _checks)
	else:
		push_error("[BELLHOLLOW ATMOSPHERE] FAIL %d/%d checks" % [_failures, _checks])
	quit(1 if _failures > 0 else 0)

func _check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		push_error("[BELLHOLLOW ATMOSPHERE] " + message)
