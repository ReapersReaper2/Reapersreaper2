extends SceneTree
## Wrath ally endgame systems — headless test.
##
## Covers: ally actor record shape; bark rotation order 01->02->03->01;
## fire meter accumulation from blue volleys (armor_bypass); lesser-form
## fires exactly at threshold (idempotent); can_plant blocks on
## inventory-only blade and passes when equipped; needs_equip_prompt true
## only in the inventory-only state; twins grant idempotent; phoenix rebirth
## idempotent single-shot. Existing old_one_gate.check() behavior is pinned
## by nineslot_widowblade_test.gd and must stay unchanged.

const WrathAlly = preload("res://scripts/wrath_ally.gd")
const OldOneGate = preload("res://scripts/old_one_gate.gd")
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


func _equip(gs: Node, weapon_id: String) -> void:
	(gs.state["player"] as Dictionary)["weapon"] = weapon_id


func _init() -> void:
	print("[wrath_ally_test] starting")
	_run.call_deferred()


func _run() -> void:
	_test_actor_record()
	_test_bark_rotation()
	_test_join()
	_test_volley_and_meter()
	_test_lesser_form()
	_test_can_plant()
	_test_needs_equip_prompt()
	_test_twins_grant()
	_test_phoenix_rebirth()
	_test_check_unchanged()
	var total := _passes + _failures
	print("[TEST] wrath_ally: %d passed, %d failed (of %d)" % [_passes, _failures, total])
	if _failures > 0:
		quit(1)
	else:
		quit(0)


func _test_actor_record() -> void:
	var a := WrathAlly.actor_record()
	_check("actor_id is wrath", str(a.get("actor_id", "")) == "wrath")
	_check("side is ally", str(a.get("side", "")) == "ally")
	_check("actions has blue_fire_volley", (a.get("actions", []) as Array).has("blue_fire_volley"))
	_check("turn_order after_player", str(a.get("turn_order", "")) == "after_player")
	_check("tactics scripted_beats", str(a.get("tactics", "")) == "scripted_beats")


func _test_bark_rotation() -> void:
	var gs = _make_gs()
	_check("bark 1", WrathAlly.next_volley_bark(gs) == "wrath_blue_volley_01")
	_check("bark 2", WrathAlly.next_volley_bark(gs) == "wrath_blue_volley_02")
	_check("bark 3", WrathAlly.next_volley_bark(gs) == "wrath_blue_volley_03")
	_check("bark wraps to 01", WrathAlly.next_volley_bark(gs) == "wrath_blue_volley_01")
	_check("bark 02 again", WrathAlly.next_volley_bark(gs) == "wrath_blue_volley_02")


func _test_join() -> void:
	var gs = _make_gs()
	var j := WrathAlly.join_ally(gs)
	_check("join bark slot id", str(j.get("bark", "")) == "wrath_oldone_entrance")
	_check("join first true", bool(j.get("first", false)))
	var j2 := WrathAlly.join_ally(gs)
	_check("join idempotent (first false)", not bool(j2.get("first", true)))
	_check("join sets flag", gs.get_flag("wrath_ally_joined", false))


func _test_volley_and_meter() -> void:
	var gs = _make_gs()
	_check("glow blue when armed", WrathAlly.glow_state(gs) == "blue")
	_check("meter starts 0", WrathAlly.fire_meter(gs) == 0)
	var v := WrathAlly.fire_volley(gs)
	_check("volley fired", bool(v.get("fired", false)))
	_check("volley shots 6", int(v.get("shots", 0)) == 6)
	_check("volley armor_bypass", bool(v.get("armor_bypass", false)))
	_check("volley total 24", int(v.get("damage_total", 0)) == 24)
	_check("meter accumulated 24", WrathAlly.fire_meter(gs) == 24)
	_check("volley enters breath reload", bool(v.get("breath_reload", false)))
	_check("glow green in reload", WrathAlly.glow_state(gs) == "green")
	# A second volley during the reload beat must NOT fire.
	var v2 := WrathAlly.fire_volley(gs)
	_check("volley blocked in reload", not bool(v2.get("fired", true)))
	_check("meter unchanged during reload", WrathAlly.fire_meter(gs) == 24)
	var b := WrathAlly.take_breath(gs)
	_check("breath clears reload", not bool(b.get("breath_reload", true)))
	_check("glow blue after breath", WrathAlly.glow_state(gs) == "blue")
	var v3 := WrathAlly.fire_volley(gs)
	_check("volley fires again after breath", bool(v3.get("fired", false)))
	_check("meter accumulated 48", WrathAlly.fire_meter(gs) == 48)
	_check("volley bark slot only (no lines)", str(v3.get("bark", "")).begins_with("wrath_blue_volley_"))


func _test_lesser_form() -> void:
	var gs = _make_gs()
	# 24 = below threshold: no transform.
	gs.set_stat("wrath_bark_idx", 0)  # keep bark state out of the way
	WrathAlly.fire_volley(gs)
	_check("no lesser form below threshold", not gs.get_flag("old_one_lesser_form", false))
	var l := WrathAlly.check_lesser_form(gs)
	_check("check returns fired false", not bool(l.get("fired", true)))
	WrathAlly.take_breath(gs)
	WrathAlly.fire_volley(gs)  # meter now 48 = threshold
	_check("lesser form fires at threshold", gs.get_flag("old_one_lesser_form", false))
	var l2 := WrathAlly.check_lesser_form(gs)
	_check("lesser form idempotent", not bool(l2.get("fired", true)))
	var l3 := WrathAlly.check_lesser_form(gs)
	_check("lesser form stays idempotent", not bool(l3.get("fired", true)))


func _test_can_plant() -> void:
	# Inventory-only blade, no lesser form: blocked.
	var gs = _make_gs()
	gs.add_item("widowblade", 1)
	var p1 := OldOneGate.can_plant(gs)
	_check("can_plant blocked pre lesser form", not bool(p1.get("ok", true)))
	# Inventory-only blade, lesser form fired: still blocked (must EQUIP).
	for i in WrathAlly.LESSER_FORM_THRESHOLD:
		gs.bump_counter(WrathAlly.FIRE_METER)
	WrathAlly.check_lesser_form(gs)
	var p2 := OldOneGate.can_plant(gs)
	_check("can_plant blocks inventory-only", not bool(p2.get("ok", true)))
	_check("can_plant gives equip reason", str(p2.get("reason", "")).find("equipped") >= 0)
	# Equipped blade + lesser form: passes.
	_equip(gs, "widowblade")
	var p3 := OldOneGate.can_plant(gs)
	_check("can_plant passes when equipped", bool(p3.get("ok", false)))
	# plant() wiring delegates to the gate.
	var w := WrathAlly.plant(gs)
	_check("plant ok", bool(w.get("ok", false)))
	var w2 := WrathAlly.plant(gs)
	_check("plant idempotent", bool(w2.get("ok", false)) and not bool(w2.get("first", true)))
	var gs2 = _make_gs()
	gs2.add_item("widowblade", 1)
	_equip(gs2, "widowblade")
	_check("plant blocked without lesser form", not bool(WrathAlly.plant(gs2).get("ok", true)))


func _test_needs_equip_prompt() -> void:
	var none = _make_gs()
	_check("no prompt without blade", not OldOneGate.needs_equip_prompt(none))
	var inv = _make_gs()
	inv.add_item("widowblade", 1)
	_check("prompt when inventory-only", OldOneGate.needs_equip_prompt(inv))
	_equip(inv, "widowblade")
	_check("no prompt when equipped", not OldOneGate.needs_equip_prompt(inv))
	var eq = _make_gs()
	_equip(eq, "widowblade")
	_check("no prompt when equipped-only", not OldOneGate.needs_equip_prompt(eq))


func _test_twins_grant() -> void:
	var gs = _make_gs()
	var e := WrathAlly.on_old_one_fight_end(gs)
	_check("twins granted first call", bool(e.get("granted", false)))
	_check("twins item count 1", gs.get_item_count("twins_lent") == 1)
	_check("twins flag set", gs.get_flag("twins_keepable_granted", false))
	_check("fight end bark slot id", str(e.get("bark", "")) == "wrath_fight_end")
	var e2 := WrathAlly.on_old_one_fight_end(gs)
	_check("twins grant idempotent", not bool(e2.get("granted", true)))
	_check("twins count stays 1", gs.get_item_count("twins_lent") == 1)


func _test_phoenix_rebirth() -> void:
	var gs = _make_gs()
	var r := WrathAlly.fire_phoenix_rebirth(gs)
	_check("rebirth event name", str(r.get("event", "")) == "old_one_phase_claimed")
	_check("rebirth flag id", str(r.get("flag", "")) == "wrath_phoenix_rebirth")
	_check("rebirth first true", bool(r.get("first", false)))
	_check("rebirth flag set", gs.get_flag("wrath_phoenix_rebirth", false))
	var r2 := WrathAlly.fire_phoenix_rebirth(gs)
	_check("rebirth second call not first", not bool(r2.get("first", true)))
	_check("rebirth event stable", str(r2.get("event", "")) == "old_one_phase_claimed")
	_check("rebirth idempotent single flag", gs.get_flag("wrath_phoenix_rebirth", false))


func _test_check_unchanged() -> void:
	# Pin the pre-existing gate behavior (Gage's ruling, signed off 2026-10-04).
	var gs = _make_gs()
	var g := OldOneGate.check(gs)
	_check("check still blocked pre-ivy", not bool(g.get("ok", true)))
	gs.set_flag("ivy_defeated", true)
	var g2 := OldOneGate.check(gs)
	_check("check still blocked without blade", not bool(g2.get("ok", true)))
	gs.add_item("widowblade", 1)
	var g3 := OldOneGate.check(gs)
	_check("check still opens with blade", bool(g3.get("ok", false)))
