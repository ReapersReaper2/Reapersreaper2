extends SceneTree
## Director D-48: one ripe fruit is spent for each distinct offer regardless
## of the creature's later choice; no edible traits or automatic bonding.
## godot --headless --path godot-project --script res://scripts/fruit_offer_test.gd

const Fruit := preload("res://scripts/fruit_traits.gd")
const Memory := preload("res://scripts/offer_memory.gd")
const GameState := preload("res://scripts/game_state.gd")

var _checks := 0
var _fails := 0

func _initialize() -> void:
	call_deferred("_run")

func _make_fruit(gs: Node, foe_id: String, enc: String, at_step: int) -> String:
	var foe := {
		"foe_id": foe_id, "enc_ref": enc, "tier": "Skeletal Body",
		"fruit_eligibility": "eligible", "corpse_produced": true,
		"mortal_world": false
	}
	var emergence := Fruit.emerge_plant(gs, foe, "c1", "necro",
		"trait_shika_claw", at_step)
	if not bool(emergence.get("ok", false)):
		return ""
	var plant: Dictionary = emergence["plant"]
	var id := str(plant["plant_id"])
	Fruit.finish_growth(gs, id, at_step)
	var harvested := Fruit.harvest_fruit(gs, id, at_step)
	if not bool(harvested.get("ok", false)):
		return ""
	return str((harvested["carried"] as Dictionary)["fruit_id"])

func _run() -> void:
	var gs := GameState.new()
	gs.new_game()
	var fruit_id := _make_fruit(gs, "foe_a", "ENC-029", 100)
	_check(not fruit_id.is_empty(), "canon fruit lifecycle produces offerable fruit")
	if fruit_id.is_empty():
		push_error("[FRUIT OFFER] Fixture could not harvest first fruit")
		quit(1)
		return
	_check(Fruit.carried(gs).size() == 1, "fruit starts in carried inventory")
	var active_before := Fruit.active_traits(gs).size()
	var tokens_before := Fruit.tokens(gs).size()
	var earned_before := Fruit.ledger(gs).duplicate(true)
	_check(not Fruit.offer_fruit(gs, fruit_id, "", 101)["ok"],
		"missing stable offer reference is rejected")
	_check(Fruit.carried(gs).size() == 1,
		"invalid offer cannot spend fruit")
	var payment := Fruit.offer_fruit(gs, fruit_id, "individual-A.offer-1", 101)
	_check(bool(payment.get("ok", false)) and bool(payment.get("changed", false)),
		"first real offer spends one unrotted fruit")
	if not bool(payment.get("ok", false)):
		push_error("[FRUIT OFFER] Payment failed early: " + str(payment))
		quit(1)
		return
	_check(Fruit.carried(gs).is_empty(), "offered fruit leaves carried inventory")
	var receipt: Dictionary = (Fruit._player_fruit(gs)["offered"] as Array)[0]
	_check(receipt.get("fruit_id", "") == fruit_id and
		receipt.get("offer_ref", "") == "individual-A.offer-1" and
		int(receipt.get("offered_at_step", -1)) == 101,
		"receipt saves fruit identity and exact offer step")
	_check(Fruit.active_traits(gs).size() == active_before and
		Fruit.tokens(gs).size() == tokens_before,
		"offering fruit grants no eating traits or cosmetic tokens")
	_check((Fruit._player_fruit(gs)["eaten"] as Array).is_empty(),
		"offered fruit never enters eaten history")
	_check(int(Fruit.ledger(gs).get("necro_count", 0)) ==
		int(earned_before.get("necro_count", 0)),
		"fruit offered to another creature does not count as player eating")
	var harvest_rows: Array = Fruit.ledger(gs)["harvested"]
	_check(harvest_rows.size() == 1 and
		str((harvest_rows[0] as Dictionary).get("outcome", "")) == "offered",
		"one shared fruit ledger records the offered outcome")
	var retry := Fruit.offer_fruit(gs, fruit_id, "individual-A.offer-1", 110)
	_check(bool(retry.get("ok", false)) and not bool(retry.get("changed", true)),
		"double tap/replayed animation does not spend fruit twice")
	_check((Fruit._player_fruit(gs)["offered"] as Array).size() == 1,
		"idempotent retry never duplicates receipts")
	_check(not Fruit.offer_fruit(gs, fruit_id, "individual-B.offer-2", 112)["ok"],
		"spent fruit cannot pay for another creature's offer")

	var other_id := _make_fruit(gs, "foe_b", "ENC-030", 120)
	_check(not other_id.is_empty(), "second fruit is independently harvestable")
	if other_id.is_empty():
		push_error("[FRUIT OFFER] Fixture could not harvest second fruit")
		quit(1)
		return
	var conflict := Fruit.offer_fruit(gs, other_id, "individual-A.offer-1", 121)
	_check(not conflict["ok"] and str(conflict["reason"]) == "offer_ref_conflict",
		"same offer event cannot be charged against a different fruit")
	_check(Fruit.carried(gs).size() == 1,
		"conflicting offer reference cannot spend second fruit")

	# The choice outcome is an independent transaction. If the animal
	# turns away, the fruit remains spent; no creature mantle is created.
	var creature := {"instance_ref": "individual-A", "mantles": [], "offer_memory": {}}
	var journal: Array = []
	var withdrew := Memory.record_outcome(creature, "individual-A", "individual-A.offer-1",
		Memory.OUTCOME_WITHDREW, journal)
	_check(bool(withdrew.get("ok", false)),
		"creature is free to reject after the fruit has been offered")
	_check(Fruit.carried(gs).size() == 1 and
		(Fruit._player_fruit(gs)["offered"] as Array).size() == 1,
		"rejection never refunds the first offered fruit")
	_check((creature["mantles"] as Array).is_empty() and
		bool(Memory.snapshot(creature).get("reoffer_blocked", false)),
		"rejection has no mantle, only the approved re-offer guard")
	var serialized: Variant = JSON.parse_string(JSON.stringify(gs.state))
	var persisted_offers := 0
	if serialized is Dictionary:
		var saved_player: Dictionary = (serialized as Dictionary).get("player", {})
		var saved_fruit: Dictionary = saved_player.get("fruit", {})
		var offered: Array = saved_fruit.get("offered", [])
		persisted_offers = offered.size()
	_check(persisted_offers == 1,
		"offered receipt survives normal JSON save and load")

	# A different ripe fruit can be used for a different offer.
	_check(Fruit.offer_fruit(gs, other_id, "individual-B.offer-1", 122)["ok"],
		"another individual can be offered the remaining ripe fruit")
	_check(Fruit.carried(gs).is_empty() and
		(Fruit._player_fruit(gs)["offered"] as Array).size() == 2,
		"each distinct offer charges exactly one fruit")

	var gs_rotted := GameState.new()
	gs_rotted.new_game()
	var expired := _make_fruit(gs_rotted, "foe_c", "ENC-031", 100)
	if expired.is_empty():
		push_error("[FRUIT OFFER] Fixture could not harvest expired fruit")
		quit(1)
		return
	var bad := Fruit.offer_fruit(gs_rotted, expired, "individual-C.offer-1", 1300)
	_check(not bool(bad.get("ok", false)) and str(bad.get("reason", "")) == "rotted",
		"rotted fruit cannot be used for bonding")
	_check(Fruit.carried(gs_rotted).size() == 1 and
		(Fruit._player_fruit(gs_rotted).get("offered", []) as Array).is_empty(),
		"rotted refusal leaves inventory and receipts unchanged")
	_check(not Fruit.offer_fruit(gs_rotted, expired, "individual-C.offer-1", 90)["ok"],
		"backdated offer before fruit emergence is forbidden")

	if _fails == 0:
		print("[FRUIT OFFER] PASS %d checks" % _checks)
	else:
		push_error("[FRUIT OFFER] FAIL %d/%d" % [_fails, _checks])
	quit(1 if _fails > 0 else 0)

func _check(ok: bool, description: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
		push_error("[FRUIT OFFER] " + description)
