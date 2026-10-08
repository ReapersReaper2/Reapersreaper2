extends SceneTree
## Living Fabricator grafts — headless test.
##
## Covers: the six locked traits, feed/learn flow, in-fiction refusals,
## slot limits (weapon 1, armor 2, permanent grafts), one-shot
## applications (key/bridge/prosthetic), effect hooks (thorn retaliation,
## cinder mitigation), Journal page data, save/load round-trip.

const Fabricator = preload("res://scripts/fabricator.gd")
const GameStateScript := preload("res://scripts/game_state.gd")
const JournalScript := preload("res://scripts/journal.gd")

var _failures := 0
var _passes := 0


func _check(name: String, cond: bool) -> void:
	if cond:
		_passes += 1
		print("  PASS: ", name)
	else:
		_failures += 1
		print("  FAILED: ", name)


func _make_gs() -> Node:
	var gs = GameStateScript.new()
	gs.save_system = null
	gs.new_game()
	return gs


func _init() -> void:
	print("[fabricator_test] starting")
	_run.call_deferred()


func _run() -> void:
	_test_traits()
	_test_learn()
	_test_graft_slots()
	_test_applications()
	_test_effects()
	_test_journal()
	var total := _passes + _failures
	print("[TEST] fabricator: %d passed, %d failed (of %d)" % [_passes, _failures, total])
	if _failures > 0:
		quit(1)
	else:
		quit(0)


func _test_traits() -> void:
	var ids: Array = Fabricator.trait_ids()
	_check("six locked traits", ids.size() == 6)
	for want in ["thorn", "cinder", "blade", "keyform", "bridge", "prosthetic"]:
		_check("trait %s defined" % want, want in ids)
	_check("thorn is armor slot", Fabricator.trait_slot("thorn") == "armor")
	_check("cinder is armor slot", Fabricator.trait_slot("cinder") == "armor")
	_check("blade is weapon slot", Fabricator.trait_slot("blade") == "weapon")
	_check("keyform is utility", Fabricator.trait_slot("keyform") == "utility")
	_check("bridge is world", Fabricator.trait_slot("bridge") == "world")
	_check("prosthetic is quest", Fabricator.trait_slot("prosthetic") == "quest")
	_check("thorn feeds on briar_thorns", Fabricator.feedstock_for("thorn") == "briar_thorns")
	_check("cinder feeds on ash_bark", Fabricator.feedstock_for("cinder") == "ash_bark")
	_check("blade feeds on broken_sword", Fabricator.feedstock_for("blade") == "broken_sword")
	_check("keyform feeds on rusted_key", Fabricator.feedstock_for("keyform") == "rusted_key")
	_check("bridge feeds on iron_beam", Fabricator.feedstock_for("bridge") == "iron_beam")
	_check("prosthetic feeds on silvered_ore", Fabricator.feedstock_for("prosthetic") == "silvered_ore")
	_check("names resolve", Fabricator.trait_name("thorn") == "Thorn Graft")
	_check("unknown trait slot empty", Fabricator.trait_slot("nope") == "")


func _test_learn() -> void:
	var gs = _make_gs()
	_check("nothing learned at start", Fabricator.learned(gs).is_empty())
	# Curated feed works and consumes the item.
	gs.add_item("briar_thorns", 2)
	var res: Dictionary = Fabricator.learn(gs, "briar_thorns")
	_check("learn thorn ok", bool(res["ok"]))
	_check("learn reports trait", str(res["trait"]) == "thorn")
	_check("feed consumes item", gs.get_item_count("briar_thorns") == 1)
	_check("thorn learned", Fabricator.is_learned(gs, "thorn"))
	# Learning twice is idempotent.
	res = Fabricator.learn(gs, "briar_thorns")
	_check("relearn ok", bool(res["ok"]))
	_check("no duplicate learned", Fabricator.learned(gs).count("thorn") == 1)
	# Non-curated feed is refused in-fiction, no crash, no consume.
	var snares_before: int = gs.get_item_count("soul_snare")
	res = Fabricator.learn(gs, "soul_snare")
	_check("non-curated refused", not bool(res["ok"]))
	_check("refusal has text", str(res["msg"]) != "")
	_check("refused item not consumed", gs.get_item_count("soul_snare") == snares_before)
	# Feeding without the item fails.
	res = Fabricator.learn(gs, "ash_bark")
	_check("feed without item fails", not bool(res["ok"]))
	# Refusals vary (deterministic per item).
	var r1: String = Fabricator.learn(gs, "moon_ale")["msg"]
	var r2: String = Fabricator.learn(gs, "soul_snare")["msg"]
	_check("refusals are in-fiction", r1.begins_with("[WIRING]") and r2.begins_with("[WIRING]"))


func _test_graft_slots() -> void:
	var gs = _make_gs()
	# Can't graft what isn't learned.
	var res: Dictionary = Fabricator.graft(gs, "thorn")
	_check("graft unlearned fails", not bool(res["ok"]))
	gs.add_item("briar_thorns", 1)
	gs.add_item("ash_bark", 1)
	gs.add_item("broken_sword", 1)
	Fabricator.learn(gs, "briar_thorns")
	Fabricator.learn(gs, "ash_bark")
	Fabricator.learn(gs, "broken_sword")
	# Armor slots: 2.
	res = Fabricator.graft(gs, "thorn")
	_check("graft thorn ok", bool(res["ok"]))
	_check("thorn grafted", Fabricator.has_graft(gs, "thorn"))
	res = Fabricator.graft(gs, "cinder")
	_check("graft cinder ok", bool(res["ok"]))
	_check("armor slots both filled", Fabricator.grafted_armor(gs) == ["thorn", "cinder"])
	# Weapon slot: 1.
	res = Fabricator.graft(gs, "blade")
	_check("graft blade ok", bool(res["ok"]))
	_check("blade grafted", Fabricator.has_graft(gs, "blade"))
	_check("weapon slot reports blade", Fabricator.grafted_weapon(gs) == "blade")
	# Grafts are permanent: filled slots fail safe.
	gs.add_item("briar_thorns", 1)
	Fabricator.learn(gs, "briar_thorns")
	res = Fabricator.graft(gs, "thorn")
	_check("re-graft thorn fails safe", not bool(res["ok"]))
	_check("graft still thorn after failed overwrite", Fabricator.grafted_armor(gs)[0] == "thorn")
	_check("unknown trait graft fails", not bool(Fabricator.graft(gs, "nope")["ok"]))


func _test_applications() -> void:
	var gs = _make_gs()
	gs.add_item("rusted_key", 1)
	gs.add_item("iron_beam", 1)
	gs.add_item("silvered_ore", 1)
	Fabricator.learn(gs, "rusted_key")
	Fabricator.learn(gs, "iron_beam")
	Fabricator.learn(gs, "silvered_ore")
	# Key-form: one-use replica key.
	var res: Dictionary = Fabricator.graft(gs, "keyform")
	_check("keyform applies", bool(res["ok"]))
	_check("living key granted", gs.get_item_count("living_key") == 1)
	_check("keyform consumed (re-feed to regrow)", not Fabricator.is_learned(gs, "keyform"))
	# Bridge: world-state flag.
	res = Fabricator.graft(gs, "bridge")
	_check("bridge applies", bool(res["ok"]))
	_check("bridge flag set", gs.get_flag("f2_bridge_repaired"))
	_check("bridge consumed", not Fabricator.is_learned(gs, "bridge"))
	# Prosthetic: quest flag only.
	res = Fabricator.graft(gs, "prosthetic")
	_check("prosthetic applies", bool(res["ok"]))
	_check("prosthetic flag set", gs.get_flag("fabricator_prosthetic_grown"))
	_check("prosthetic consumed", not Fabricator.is_learned(gs, "prosthetic"))
	# Applying an unlearned one-shot fails.
	_check("re-apply keyform fails", not bool(Fabricator.graft(gs, "keyform")["ok"]))


func _test_effects() -> void:
	var gs = _make_gs()
	_check("no thorn retaliation ungrafted", Fabricator.thorn_retaliation(gs) == 0)
	_check("no cinder mitigation ungrafted", Fabricator.cinder_mitigation(gs, ["fire"]) == 0)
	gs.add_item("briar_thorns", 1)
	gs.add_item("ash_bark", 1)
	Fabricator.learn(gs, "briar_thorns")
	Fabricator.learn(gs, "ash_bark")
	Fabricator.graft(gs, "thorn")
	Fabricator.graft(gs, "cinder")
	_check("thorn retaliation = 1", Fabricator.thorn_retaliation(gs) == 1)
	_check("cinder mitigates fire", Fabricator.cinder_mitigation(gs, ["fire"]) == 1)
	_check("cinder mitigates ash", Fabricator.cinder_mitigation(gs, ["ash"]) == 1)
	_check("cinder ignores physical", Fabricator.cinder_mitigation(gs, ["physical"]) == 0)
	_check("cinder ignores empty tags", Fabricator.cinder_mitigation(gs, []) == 0)


func _test_journal() -> void:
	var gs = _make_gs()
	var j = JournalScript.new()
	j.game_state = gs
	_check("journal has 5 tabs", JournalScript.TABS.size() == 5)
	_check("fabricator tab named", JournalScript.TABS[3] == "FABRICATOR")
	gs.add_item("broken_sword", 1)
	Fabricator.learn(gs, "broken_sword")
	Fabricator.graft(gs, "blade")
	_check("journal sees learned", "blade" in Fabricator.learned(gs))
	_check("journal sees weapon graft", Fabricator.grafted_weapon(gs) == "blade")
	# Save/load round-trip: fabricator state survives JSON.
	var snap: String = JSON.stringify(gs.state["fabricator"])
	var back = JSON.parse_string(snap)
	_check("fabricator state serializes", back is Dictionary)
	_check("learned survives", (back.get("learned", []) as Array).has("blade"))
	_check("grafts survive", str((back.get("grafts", {}) as Dictionary).get("weapon", "")) == "blade")
	j.queue_free()
