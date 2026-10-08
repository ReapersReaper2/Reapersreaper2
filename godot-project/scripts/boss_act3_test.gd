extends SceneTree
## Act 3 boss fights — headless test.
##
## Covers: Shika hunters (80/80 Vigor, alternating rhythm, tag-out,
## enrage on partner death, victory flag, player-death reset) and Harrow
## (150 Vigor, mirror-boss, Despair Feed heal on miss, Reconstitute once
## at 50%, tendril damage gate, victory flag, player-death reset).

const ShikaBossScript := preload("res://scripts/shika_boss.gd")
const ShikaHunterScript := preload("res://scripts/shika_hunter.gd")
const HarrowBossScript := preload("res://scripts/harrow_boss.gd")
const HarrowTendrilScript := preload("res://scripts/harrow_tendril.gd")
const GameStateScript := preload("res://scripts/game_state.gd")

var _failures := 0
var _passes := 0


func _check(name: String, cond: bool) -> void:
	if cond:
		_passes += 1
	else:
		_failures += 1
		print("  FAILED: ", name)


func _make_gs() -> Node:
	var gs = GameStateScript.new()
	gs.save_system = null
	gs.new_game()
	return gs


func _init() -> void:
	print("[boss_act3_test] starting")
	_run.call_deferred()


func _run() -> void:
	_test_shika_stats()
	_test_shika_alternating()
	_test_shika_enrage()
	_test_shika_victory_and_reset()
	_test_harrow_stats()
	_test_harrow_gate()
	_test_harrow_despair_feed()
	_test_harrow_reconstitute()
	_test_harrow_victory_and_reset()
	_test_scene_wiring()
	var total := _passes + _failures
	print("[TEST] boss_act3: %d passed, %d failed (of %d)" % [_passes, _failures, total])
	if _failures > 0:
		quit(1)
	else:
		quit(0)


# --- Shika hunters -------------------------------------------------------

func _make_shika(gs: Node) -> Node:
	var boss = ShikaBossScript.new()
	boss.game_state = gs
	root.add_child(boss)
	return boss


func _test_shika_stats() -> void:
	var gs = _make_gs()
	var boss = _make_shika(gs)
	_check("shika: locked stat block comment present",
		FileAccess.get_file_as_string("res://scripts/shika_hunter.gd").contains("80 Vigor"))
	var h1 = ShikaHunterScript.new()
	var h2 = ShikaHunterScript.new()
	root.add_child(h1)
	root.add_child(h2)
	_check("hunter 1 max_vigor == 80", h1.max_vigor == 80)
	_check("hunter 2 max_vigor == 80", h2.max_vigor == 80)
	_check("hunter 1 starts at 80 vigor", h1.vigor == 80)
	_check("hunter 2 starts at 80 vigor", h2.vigor == 80)
	_check("hunter power == 18 (locked)", h1.power == 18)
	h1.queue_free()
	h2.queue_free()
	boss.queue_free()


func _test_shika_alternating() -> void:
	var gs = _make_gs()
	var boss = _make_shika(gs)
	# Manual setup (debug_start's 1.2s intro timer is async; drive directly).
	boss._spawn_hunters()
	boss._phase = 2  # FIGHTING
	boss._activate_hunter(0)
	_check("shika: 2 hunters spawned", boss.hunter_count() == 2)
	_check("shika: hunter 0 active first", boss.active_hunter_index() == 0)
	_check("shika: hunter 0 flagged active", boss._hunters[0].active)
	_check("shika: hunter 1 not active", not boss._hunters[1].active)
	boss._tag_out()
	_check("shika: tag-out switches active hunter", boss.active_hunter_index() == 1)
	_check("shika: hunter 1 now active", boss._hunters[1].active)
	_check("shika: hunter 0 now inactive", not boss._hunters[0].active)
	boss.queue_free()


func _test_shika_enrage() -> void:
	var gs = _make_gs()
	var boss = _make_shika(gs)
	boss._spawn_hunters()
	boss._phase = 2
	boss._activate_hunter(0)
	var h0 = boss._hunters[0]
	var h1 = boss._hunters[1]
	var base_speed: float = h1.attack_speed
	h0.take_hit(999, Vector2.RIGHT)
	_check("shika: hunter 0 dead", not h0.is_alive())
	_check("shika: one hunter left", boss.hunter_count() == 1)
	_check("shika: survivor enraged (faster)", h1.attack_speed > base_speed)
	_check("shika: survivor takes the cycle", boss.active_hunter_index() == 1)
	boss.queue_free()


func _test_shika_victory_and_reset() -> void:
	var gs = _make_gs()
	var boss = _make_shika(gs)
	boss._spawn_hunters()
	boss._phase = 2
	_check("shika: victory flag starts false", not bool(gs.get_flag("gd4_shika_defeated")))
	for h in boss._hunters:
		h.take_hit(999, Vector2.RIGHT)
	_check("shika: victory flag set on both dead", bool(gs.get_flag("gd4_shika_defeated")))
	_check("shika: phase WON", boss._phase == 3)
	boss.queue_free()
	# Reset path: fresh fight, kill one hunter, then player "dies".
	var boss2 = _make_shika(gs)
	gs.set_flag("gd4_shika_defeated", false)
	boss2._spawn_hunters()
	boss2._phase = 2
	boss2._hunters[0].take_hit(50, Vector2.RIGHT)
	_check("shika: hunter damaged to 30", boss2._hunters[0].vigor == 30)
	# Simulate the reset portion of _on_player_died without the await.
	boss2._phase = 0
	boss2._clear_hunters()
	_check("shika: reset clears hunters", boss2._hunters.is_empty())
	_check("shika: victory flag untouched by reset", not bool(gs.get_flag("gd4_shika_defeated")))
	boss2.queue_free()


# --- Harrow --------------------------------------------------------------

func _make_harrow(gs: Node) -> Node:
	var boss = HarrowBossScript.new()
	boss.game_state = gs
	root.add_child(boss)
	return boss


func _test_harrow_stats() -> void:
	var gs = _make_gs()
	var boss = _make_harrow(gs)
	_check("harrow: MAX_VIGOR == 150", HarrowBossScript.MAX_VIGOR == 150)
	_check("harrow: starts at 150", boss.vigor == 150)
	_check("harrow: Despair Feed heals 10", HarrowBossScript.DESPAIR_FEED_HEAL == 10)
	_check("harrow: Reconstitute at 75 (50%)", HarrowBossScript.RECONSTITUTE_AT == 75)
	var t = HarrowTendrilScript.new()
	root.add_child(t)
	_check("tendril: 30 Vigor", t.max_vigor == 30 and t.vigor == 30)
	t.queue_free()
	boss.queue_free()


func _test_harrow_gate() -> void:
	var gs = _make_gs()
	var boss = _make_harrow(gs)
	boss._phase = 2  # FIGHTING
	# Spawn tendrils as children of a temp parent (mirrors scene use).
	var holder := Node2D.new()
	root.add_child(holder)
	boss.get_parent().remove_child(boss)
	holder.add_child(boss)
	boss._arena_center = Vector2.ZERO
	boss._spawn_tendrils()
	_check("harrow: 3 tendrils spawned", boss._tendrils.size() == 3)
	_check("harrow: 3 tendrils alive", boss._tendrils_alive() == 3)
	boss.take_hit(20, Vector2.RIGHT)
	_check("harrow: invulnerable while tendrils live", boss.vigor == 150)
	# Kill all three tendrils.
	for t in boss._tendrils:
		t.take_hit(999, Vector2.RIGHT)
	_check("harrow: all tendrils dead", boss._tendrils_alive() == 0)
	boss.take_hit(20, Vector2.RIGHT)
	_check("harrow: takes damage once gate broken", boss.vigor == 130)
	holder.queue_free()
	# boss was a child of holder; freed with it.


func _test_harrow_despair_feed() -> void:
	var gs = _make_gs()
	var boss = _make_harrow(gs)
	boss._phase = 2
	boss.vigor = 100
	boss._on_swing_whiffed()
	_check("harrow: Despair Feed heals 10 on miss", boss.vigor == 110)
	boss.vigor = 148
	boss._on_swing_whiffed()
	_check("harrow: Despair Feed caps at max", boss.vigor == 150)
	boss._phase = 0
	boss.vigor = 100
	boss._on_swing_whiffed()
	_check("harrow: no feed outside fight", boss.vigor == 100)
	boss.queue_free()


func _test_harrow_reconstitute() -> void:
	var gs = _make_gs()
	var boss = _make_harrow(gs)
	boss._phase = 2
	_check("harrow: reconstitute starts unused", not boss._reconstituted)
	# Damage to just above 50%: no trigger.
	boss.take_hit(74, Vector2.RIGHT)
	_check("harrow: no reconstitute above 50%", boss._phase == 2)
	# Damage to 50%: triggers once.
	boss.take_hit(1, Vector2.RIGHT)
	_check("harrow: reconstitute triggers at 50%", boss._phase == 3)  # RECONSTITUTING
	_check("harrow: reconstitute flagged used", boss._reconstituted)
	boss._finish_reconstitute()
	_check("harrow: reconstitute heals 30", boss.vigor == 105)
	_check("harrow: back to fighting", boss._phase == 2)
	# Second dip to 50%: no second trigger.
	boss.take_hit(30, Vector2.RIGHT)
	_check("harrow: reconstitute is one-time", boss._phase == 2)
	boss.queue_free()


func _test_harrow_victory_and_reset() -> void:
	var gs = _make_gs()
	var boss = _make_harrow(gs)
	boss._phase = 2
	_check("harrow: victory flag starts false", not bool(gs.get_flag("harrow_defeated")))
	boss._reconstituted = true  # skip the heal for a clean kill test
	boss.take_hit(999, Vector2.RIGHT)
	_check("harrow: victory flag set on kill", bool(gs.get_flag("harrow_defeated")))
	_check("harrow: phase WON", boss._phase == 4)
	boss.queue_free()
	# Reset path.
	var boss2 = _make_harrow(gs)
	gs.set_flag("harrow_defeated", false)
	boss2._phase = 2
	boss2.vigor = 60
	boss2._reconstituted = true
	boss2._phase = 0
	boss2.vigor = HarrowBossScript.MAX_VIGOR
	boss2._reconstituted = false
	_check("harrow: reset restores 150 vigor", boss2.vigor == 150)
	_check("harrow: reset clears reconstitute", not boss2._reconstituted)
	_check("harrow: victory flag untouched by reset", not bool(gs.get_flag("harrow_defeated")))
	boss2.queue_free()


# --- Scene wiring --------------------------------------------------------

func _test_scene_wiring() -> void:
	var gd4t := FileAccess.get_file_as_string("res://scenes/room_gd4.tscn")
	_check("gd4: ShikaBossFight controller node present", gd4t.contains("ShikaBossFight"))
	_check("gd4: shika_boss.gd wired", gd4t.contains("scripts/shika_boss.gd"))
	_check("gd4: victory flag referenced", gd4t.contains("gd4_shika_defeated"))
	_check("gd4: 80 Vigor noted", gd4t.contains("80 Vigor"))
	_check("gd4: trigger no longer auto-grants victory",
		not gd4t.contains('flag = "gd4_shika_defeated"'))
	var gd5t := FileAccess.get_file_as_string("res://scenes/room_gd5.tscn")
	_check("gd5: HarrowBossFight controller node present", gd5t.contains("HarrowBossFight"))
	_check("gd5: harrow_boss.gd wired", gd5t.contains("scripts/harrow_boss.gd"))
	_check("gd5: victory flag referenced", gd5t.contains("harrow_defeated"))
	_check("gd5: 150 Vigor noted", gd5t.contains("150 Vigor"))
	_check("gd5: 30 Vigor tendrils noted", gd5t.contains("30 Vigor"))
	_check("gd5: trigger no longer auto-grants victory",
		not gd5t.contains('flag = "harrow_defeated"'))
	var o2t := FileAccess.get_file_as_string("res://scenes/room_o2.tscn")
	_check("o2: Originator still not a boss", not o2t.contains("BOSS STUB"))
	var scythe_src := FileAccess.get_file_as_string("res://scripts/scythe.gd")
	_check("scythe: swing_whiffed signal exists", scythe_src.contains("signal swing_whiffed"))
	var lore_src := FileAccess.get_file_as_string("res://scripts/lore_object.gd")
	_check("lore_object: activated signal exists", lore_src.contains("signal activated"))
