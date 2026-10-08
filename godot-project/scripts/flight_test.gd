extends SceneTree
## Flight (Form 9) — headless test.
##
## Covers: Flight.can_fly gate (flag combinations), locked hints, player
## take_off/land/toggle, collision-mask switching (fly-over barriers),
## flight speed multiplier, no-fly-zone forced landing, U4 launch beat,
## and depower interaction (no flight while depowered).

const Flight := preload("res://scripts/flight.gd")
const Depower := preload("res://scripts/depower.gd")
const GameStateScript := preload("res://scripts/game_state.gd")
const PlayerScript := preload("res://scripts/player.gd")
const BarrierScript := preload("res://scripts/flyover_barrier.gd")
const NoFlyScript := preload("res://scripts/no_fly_zone.gd")
const LaunchScript := preload("res://scripts/flight_launch.gd")
const LoreScript := preload("res://scripts/lore_object.gd")

var _failures := 0
var _passes := 0


func _check(name: String, cond: bool) -> void:
	if cond:
		_passes += 1
	else:
		_failures += 1
		print("  FAILED: ", name)


func _make_gs() -> Node:
	# Use the autoload GameState: player._game_state() resolves
	# /root/GameState, and autoloads load even in headless -s runs.
	# new_game() resets flags to a known clean state.
	var gs: Node = root.get_node("GameState")
	gs.new_game()
	return gs


func _make_player_with_gs(_gs: Node) -> Node:
	var player = PlayerScript.new()
	player.name = "Player"
	player.add_to_group("player")
	root.add_child(player)  # _ready runs: mask = WALK_MASK
	return player


func _free_node(n: Node) -> void:
	if is_instance_valid(n):
		if n.get_parent() != null:
			n.get_parent().remove_child(n)
		n.free()  # immediate: queue_free leaves stale /root/GameState lookups


func _init() -> void:
	print("[flight_test] starting")
	_run.call_deferred()


func _run() -> void:
	_test_gate()
	_test_hints()
	_test_takeoff_land()
	_test_masks_and_speed()
	_test_nofly_zone()
	_test_u4_launch()
	_test_constants()
	var total := _passes + _failures
	print("[TEST] flight: %d passed, %d failed (of %d)" % [_passes, _failures, total])
	if _failures > 0:
		quit(1)
	else:
		quit(0)


func _test_gate() -> void:
	# No flags at all: depower NONE but no wings -> no flight.
	var gs := _make_gs()
	_check("gate: no flags -> cannot fly", not Flight.can_fly(gs))
	# form9 alone (no depower flags): state NONE + flag -> can fly.
	gs.set_flag("form9_unlocked", true)
	_check("gate: form9 alone -> can fly", Flight.can_fly(gs))
	# Full depower kills flight even with the flag.
	gs.set_flag("ch13_depowered", true)
	_check("gate: FULL depower + form9 -> cannot fly", not Flight.can_fly(gs))
	# Partial repower is still not NONE -> no flight.
	gs.set_flag("ch13_repowered_partial", true)
	_check("gate: PARTIAL + form9 -> cannot fly", not Flight.can_fly(gs))
	# Full repower (U3 wings beat state) -> flight.
	gs.set_flag("ch13_repowered", true)
	_check("gate: repowered + form9 -> can fly", Flight.can_fly(gs))
	# Repower without the wing flag -> no flight.
	var gs2 := _make_gs()
	gs2.set_flag("ch13_repowered", true)
	_check("gate: repowered, no form9 -> cannot fly", not Flight.can_fly(gs2))
	# Null gamestate is safe.
	_check("gate: null gs -> cannot fly", not Flight.can_fly(null))


func _test_hints() -> void:
	var gs := _make_gs()
	gs.set_flag("form9_unlocked", true)
	_check("hint: flyable -> empty hint", Flight.locked_hint(gs) == "")
	gs.set_flag("ch13_depowered", true)
	var h1: String = Flight.locked_hint(gs)
	_check("hint: depowered mentions depower", "depower" in h1.to_lower())
	var gs2 := _make_gs()
	var h2: String = Flight.locked_hint(gs2)
	_check("hint: no wings mentions wings", "wing" in h2.to_lower())


func _test_takeoff_land() -> void:
	var gs := _make_gs()
	var player := _make_player_with_gs(gs)
	_check("player: starts grounded", not player.flying)
	_check("player: starts with walk mask", player.collision_mask == Flight.WALK_MASK)
	# Locked: no wings -> stays grounded.
	player.try_toggle_flight()
	_check("player: toggle without unlock stays grounded", not player.flying)
	# Unlock and take off.
	gs.set_flag("form9_unlocked", true)
	player.try_toggle_flight()
	_check("player: toggle with unlock takes off", player.flying)
	_check("player: flying uses fly mask", player.collision_mask == Flight.FLY_MASK)
	# Toggle again lands.
	player.try_toggle_flight()
	_check("player: second toggle lands", not player.flying)
	_check("player: landed restores walk mask", player.collision_mask == Flight.WALK_MASK)
	# Direct take_off/land.
	player.take_off()
	_check("player: take_off works", player.flying)
	player.land()
	_check("player: land works", not player.flying)
	# land() when grounded is a no-op.
	player.land()
	_check("player: land when grounded stays grounded", not player.flying)
	# Blocked while move_locked (e.g. mid-swing).
	player.move_locked = true
	player.take_off()
	_check("player: take_off blocked while move_locked", not player.flying)
	player.move_locked = false
	# Blocked while tendril riding.
	player.tendril_riding = true
	player.take_off()
	_check("player: take_off blocked while tendril_riding", not player.flying)
	player.tendril_riding = false
	# Depowered mid-flight state can't re-take-off after landing.
	player.take_off()
	_check("player: airborne before depower test", player.flying)
	player.land()
	gs.set_flag("ch13_depowered", true)
	player.try_toggle_flight()
	_check("player: cannot take off while depowered", not player.flying)
	_free_node(player)


func _test_masks_and_speed() -> void:
	_check("masks: fly layer is 8", Flight.FLY_LAYER == 8)
	_check("masks: walk mask covers walls+flyover", Flight.WALK_MASK == 9)
	_check("masks: fly mask is walls only", Flight.FLY_MASK == 1)
	_check("speed: flight mult is 1.4", is_equal_approx(Flight.speed_mult(), 1.4))
	# Barrier node configures itself to the fly-over layer.
	var b := BarrierScript.new()
	root.add_child(b)  # _ready runs
	_check("barrier: layer is fly-over layer", b.collision_layer == 8)
	_check("barrier: mask is zero", b.collision_mask == 0)
	_free_node(b)


func _test_nofly_zone() -> void:
	var gs := _make_gs()
	gs.set_flag("form9_unlocked", true)
	var player := _make_player_with_gs(gs)
	player.take_off()
	_check("nofly: player airborne before zone", player.flying)
	var zone := NoFlyScript.new()
	root.add_child(zone)  # _ready runs
	# Simulate the body_entered signal path directly.
	zone._on_body_entered(player)
	_check("nofly: forced landing on entry", not player.flying)
	_check("nofly: walk mask restored", player.collision_mask == Flight.WALK_MASK)
	# Grounded player entering is unaffected.
	zone._on_body_entered(player)
	_check("nofly: grounded entry stays grounded", not player.flying)
	# Non-player bodies are ignored.
	var rock := Node2D.new()
	rock.name = "Rock"
	root.add_child(rock)
	player.take_off()
	zone._on_body_entered(rock)
	_check("nofly: non-player ignored, still flying", player.flying)
	_free_node(rock)
	_free_node(zone)
	_free_node(player)


func _test_u4_launch() -> void:
	# Build a minimal room-like parent: lore LaunchPoint + Player.
	var gs := _make_gs()
	gs.set_flag("form9_unlocked", true)
	var room := Node2D.new()
	room.name = "RoomU4Test"
	root.add_child(room)
	var launch := LoreScript.new()
	launch.name = "LaunchPoint"
	room.add_child(launch)  # _ready runs; no children, guarded
	var player := PlayerScript.new()
	player.name = "Player"
	player.add_to_group("player")
	room.add_child(player)
	var ctrl := LaunchScript.new()
	ctrl.name = "FlightLaunch"
	room.add_child(ctrl)  # _ready connects to activated
	_check("u4: controller wired to launch", ctrl._launch != null)
	_check("u4: controller found player", ctrl._player != null)
	# Fire the launch: flight available -> takeoff.
	launch.activated.emit(launch)
	_check("u4: launch takes off when unlocked", player.flying)
	# Locked case: fresh player, no wing flag.
	player.land()
	gs.set_flag("form9_unlocked", false)
	launch.activated.emit(launch)
	_check("u4: launch stays grounded when locked", not player.flying)
	_free_node(room)


func _test_constants() -> void:
	_check("consts: lift px positive", Flight.LIFT_PX > 0.0)
	_check("consts: depower flight_available agrees",
		Depower.flight_available(null) == Flight.can_fly(null))
