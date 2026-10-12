extends SceneTree
## Variant-A mantle rules and shared thread accounting, no story assumptions.
## godot --headless --path godot-project --script res://scripts/mantle_ledger_test.gd

const Mantles := preload("res://scripts/mantle_records.gd")
const Party := preload("res://scripts/party.gd")
const Breeding := preload("res://scripts/breeding.gd")
const GameState := preload("res://scripts/game_state.gd")
const SaveSystem := preload("res://scripts/save_system.gd")

var _checks := 0
var _failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var creature := Party.make_entry("snapling", 5)
	_check(creature.has("mantles") and (creature["mantles"] as Array).is_empty(),
		"new creature owns an empty mantle ledger")
	_check(bool(Mantles.validate(creature).get("ok", false)),
		"empty ledger and legacy no-ledger entries are valid")
	_check(bool(Mantles.validate({"creature_id": "snapling"}).get("ok", false)),
		"legacy creature without mantles is backward-compatible")
	_check(not Mantles.breeding_affinity(creature),
		"no expressed mantle means no qualitative affinity")
	var primary := {
		"effect_family": "CALM", "expression_state": "EXPRESSED",
		"deployment_class": "ground", "magnitude_snapshot": null,
	}
	_check(bool(Mantles.add_record(creature, primary).get("ok", false)),
		"approved expression can be written to creature sheet")
	_check(Mantles.breeding_affinity(creature),
		"breeding can read qualitative mantle affinity")
	_check(Breeding.has_mantle_affinity(creature),
		"breeding interface exposes the mantle as a read-only flag")
	primary["effect_family"] = "INVALID"
	_check(str((Mantles.records(creature)[0] as Dictionary).get("effect_family", "")) == "CALM",
		"mantle store takes a deep copy, not mutable caller data")
	var second := {
		"effect_family": "VIGOR", "expression_state": "EXPRESSED",
		"deployment_class": "waterline"
	}
	var denied := Mantles.add_record(creature, second)
	_check(not bool(denied.get("ok", false)) and str(denied.get("reason", "")) == "expressed_limit",
		"second expressed mantle is rejected; first wins")
	_check(Mantles.records(creature).size() == 1,
		"failed competing expression does not modify stored mantle")
	second["expression_state"] = "DORMANT"
	_check(bool(Mantles.add_record(creature, second).get("ok", false)),
		"non-expressed mantle can coexist without exceeding expression cap")
	var unresolved := {
		"effect_family": "NIGHTSIGHT", "expression_state": "EXPRESSED",
		"deployment_class": "UNRESOLVED"
	}
	_check(str(Mantles.add_record(creature, unresolved).get("reason", "")) == "unresolved_mantle_inert",
		"unresolved deployment cannot become an expressed mantle")
	unresolved["expression_state"] = "TENDED"
	_check(bool(Mantles.add_record(creature, unresolved).get("ok", false)),
		"unresolved deployment can be staged as inert")
	_check(str(Mantles.add_record(creature, {
		"effect_family": "SECRET", "expression_state": "DORMANT",
		"deployment_class": "ground"
	}).get("reason", "")) == "unknown_effect_family",
		"effect-family enum is closed")
	_check(str(Mantles.add_record(creature, {
		"effect_family": "CALM", "expression_state": "DORMANT",
		"deployment_class": "ground", "heritability_flag": "ECHO"
	}).get("reason", "")) == "mantle_inheritance_forbidden",
		"echo heredity is forbidden by director decision")
	_check(Mantles.records(creature).size() == 3,
		"invalid writes leave the original record set untouched")
	# Vault/party imports must never retain references to caller-owned
	# nested mantle arrays, or a later edit can mutate saved creature data.
	var gs_import = GameState.new()
	gs_import.new_game()
	var exported := creature.duplicate(true)
	_check(Party.append_entry(gs_import, exported),
		"creature with mantle record can be added to the party")
	exported["mantles"].clear()
	_check(Mantles.records(Party.get_entry(gs_import, Party.size(gs_import)-1)).size() == 3,
		"party import takes ownership of nested mantle data")
	var snapshot := Breeding._snapshot(creature)
	_check(not snapshot.has("mantles") and not snapshot.has("mantle"),
		"breeding snapshot does not carry mantle records")
	var egg := {"sire": snapshot, "dam": snapshot}
	var offspring := Breeding._make_offspring(egg)
	_check((offspring.get("mantles", []) as Array).is_empty(),
		"offspring has no inherited mantles")
	_check(not Mantles.breeding_affinity(offspring),
		"offspring receives no inherited mantle affinity")

	var gs = GameState.new()
	gs.new_game()
	_check(gs.get_soul_thread() == 0, "new run has zero thread, no invented grant")
	_check(gs.get_soul_credits() > 0, "independent Soul Credits stay untouched")
	_check(not gs.spend_soul_thread(1), "cannot debit a missing balance")
	_check(not gs.add_soul_thread(0) and not gs.add_soul_thread(-3),
		"nonpositive thread awards are rejected")
	_check(gs.add_soul_thread(7) and gs.get_soul_thread() == 7,
		"positive thread awards use the one shared ledger")
	_check(not gs.spend_soul_thread(8) and gs.get_soul_thread() == 7,
		"insufficient debit makes no write")
	_check(gs.spend_soul_thread(4) and gs.get_soul_thread() == 3,
		"one successful debit reduces balance exactly once")
	_check(gs.get_soul_credits() == GameState.STARTING_CREDITS,
		"spending thread never spends credits")
	var serialized := JSON.stringify(gs.state)
	var restored = JSON.parse_string(serialized)
	var old_state := (restored as Dictionary).duplicate(true)
	old_state.erase("soul_thread")
	gs.state = old_state
	_check(gs.get_soul_thread() == 0,
		"pre-ledger save reads as zero without a migration")
	gs.state = restored
	_check(gs.get_soul_thread() == 3,
		"thread persists through normal save JSON round-trip")
	_check(int(SaveSystem.default_save().get("soul_thread", -1)) == 0,
		"fresh saves declare shared thread field")

	if _failures > 0:
		push_error("[MANTLE LEDGER] %d/%d failed" % [_failures, _checks])
	else:
		print("[MANTLE LEDGER] PASS %d checks" % _checks)
	quit(1 if _failures > 0 else 0)

func _check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		push_error("[MANTLE LEDGER] " + message)
