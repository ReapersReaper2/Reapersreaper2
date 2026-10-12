extends SceneTree
## Creature instance identity must survive every container transition.
## Never group individual refusal/visit memory by species or party index.
## godot --headless --path godot-project --script res://scripts/creature_identity_test.gd

const Party := preload("res://scripts/party.gd")
const Storage := preload("res://scripts/storage.gd")
const OfferMemory := preload("res://scripts/offer_memory.gd")
const GameState := preload("res://scripts/game_state.gd")
const Breeding := preload("res://scripts/breeding.gd")

var _checks := 0
var _failed := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var a := Party.make_entry("snapling", 5)
	var b := Party.make_entry("snapling", 5)
	var ref_a: String = str(a.get("instance_ref", ""))
	var ref_b: String = str(b.get("instance_ref", ""))
	_check(ref_a.begins_with("creature_") and ref_a.length() == 41,
		"new creature has a valid 128-bit instance reference")
	_check(ref_b.begins_with("creature_") and ref_b != ref_a,
		"two creatures of one species receive distinct identities")
	_check(Party.ensure_instance_ref(a) == ref_a,
		"getting an existing identity does not rotate it")

	var journal: Array = []
	var mismatch := OfferMemory.record_outcome(a, ref_b, "first", OfferMemory.OUTCOME_NEUTRAL, journal)
	_check(not mismatch["ok"] and str(mismatch["reason"]) == "individual_identity_mismatch",
		"cross-animal event is rejected, even for same-species individuals")
	_check(OfferMemory.snapshot(a).is_empty() and journal.is_empty(),
		"rejected identity mismatch never mutates memory or journal")
	var without_ref := {"offer_memory": {}}
	_check(str(OfferMemory.record_outcome(without_ref, ref_a, "second",
		OfferMemory.OUTCOME_NEUTRAL, journal)["reason"]) == "creature_instance_ref_required",
		"unidentified creature cannot take part in the offer state machine")
	_check(bool(OfferMemory.record_outcome(a, ref_a, "seen-a",
		OfferMemory.OUTCOME_NEUTRAL, journal)["ok"]),
		"proper owner can register first visit")
	_check(int(OfferMemory.snapshot(a)["neutral_visits"]) == 1,
		"visit count belongs only to the actual individual")
	_check(not b.has("offer_memory") or OfferMemory.snapshot(b).is_empty(),
		"second creature is untouched")
	_check(not Breeding._snapshot(a).has("instance_ref") and
		not Breeding._snapshot(a).has("offer_memory"),
		"breeding data does not transmit individual identity/history")

	var gs := GameState.new()
	gs.new_game()
	_check(Party.append_entry(gs, a), "creature can join active party")
	var index := Party.size(gs) - 1
	var party_entry := Party.get_entry(gs, index)
	_check(str(party_entry["instance_ref"]) == ref_a, "party preserves original identity")
	var location := Storage.deposit(gs, index)
	_check(int(location[0]) >= 0, "creature can enter storage")
	var vault_entry := Storage.get_entry(gs, int(location[0]), int(location[1]))
	_check(str(vault_entry["instance_ref"]) == ref_a,
		"vault retains the individual's identity")
	party_entry["offer_memory"]["neutral_visits"] = 99
	_check(int(OfferMemory.snapshot(vault_entry)["neutral_visits"]) == 1,
		"storage deposit deep copies individual encounter history")
	_check(Storage.withdraw(gs, int(location[0]), int(location[1])),
		"same creature can be withdrawn")
	var restored := Party.get_entry(gs, Party.size(gs) - 1)
	_check(str(restored["instance_ref"]) == ref_a and
		int(OfferMemory.snapshot(restored)["neutral_visits"]) == 1,
		"vault withdrawal preserves ID and visit progress")
	var before := JSON.stringify(gs.state)
	var after = JSON.parse_string(before)
	_check(after is Dictionary, "party and identity remain JSON-safe")
	if after is Dictionary:
		var party_copy: Array = (after as Dictionary)["party"]
		var saved_entry: Dictionary = party_copy.back()
		_check(str(saved_entry.get("instance_ref", "")) == ref_a,
			"creature identity survives save/load round-trip")
		_check(int((saved_entry.get("offer_memory", {}) as Dictionary).get(
			"neutral_visits", 0)) == 1, "personal history survives save/load")

	# Pre-identity saves upgrade only on first access, retaining every other
	# attribute; no destructive save schema migration.
	var legacy := Party.make_entry("snapling", 2)
	legacy.erase("instance_ref")
	legacy["nickname"] = "Legacy Resident"
	gs.state["party"].append(legacy)
	var old_entry := Party.get_entry(gs, Party.size(gs) - 1)
	var legacy_ref := str(old_entry.get("instance_ref", ""))
	_check(legacy_ref.begins_with("creature_") and legacy_ref != ref_a,
		"legacy party creature receives a unique ID lazily")
	_check(str(old_entry.get("nickname", "")) == "Legacy Resident",
		"repair does not disturb existing nickname or stats")
	_check(Party.get_entry(gs, Party.size(gs)-1)["instance_ref"] == legacy_ref,
		"legacy ID is never regenerated on second read")
	var old_vault := Party.make_entry("snapling", 3)
	old_vault.erase("instance_ref")
	Storage._box(gs, 0).append(old_vault)
	var repaired := Storage.get_entry(gs, 0, Storage.box_count(gs, 0)-1)
	_check(str(repaired.get("instance_ref", "")).begins_with("creature_"),
		"legacy vault creature is repaired without moving it")
	_check(str(repaired["instance_ref"]) != legacy_ref,
		"legacy vault and party creatures cannot share one identity")

	var extra := Party.make_entry("snapling", 4)
	var extra_ref := str(extra["instance_ref"])
	extra["offer_memory"]["neutral_visits"] = 1
	var spot := Storage.deposit_entry(gs, extra)
	_check(int(spot[0]) >= 0, "direct battle catch deposit works")
	extra["offer_memory"]["neutral_visits"] = 55
	var stored_extra := Storage.get_entry(gs, int(spot[0]), int(spot[1]))
	_check(str(stored_extra["instance_ref"]) == extra_ref and
		int(OfferMemory.snapshot(stored_extra)["neutral_visits"]) == 1,
		"direct-to-vault deposit owns an independent copy of the entry")

	if _failed == 0:
		print("[CREATURE IDENTITY] PASS %d checks" % _checks)
	else:
		push_error("[CREATURE IDENTITY] FAIL %d/%d" % [_failed, _checks])
	quit(1 if _failed > 0 else 0)

func _check(ok: bool, description: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
		push_error("[CREATURE IDENTITY] " + description)
