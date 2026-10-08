extends SceneTree
## Fruit feeding loop — headless test.
##
## Covers the locked canon (Sweet Potato Creature, via the collab log):
##   A. Concoction: fruit identity/effects derive from host plant, seeded
##      determinism (same host + seed -> identical concoction); unknown host
##      refused; lean/effect draws stay inside the host's tables.
##   B. luna_smell(): lean revealed ONLY via the smell API; lean_known flips;
##      describe() shows "?" before and the lean after; line comes from the
##      verbatim ui_text.json feeding entries (Sweet Potato Creature,
##      collab log 2026-10-05: story-lane sign-off, must never be
##      paraphrased on the wiring side).
##   C. Power hidden until eaten: describe() reports "unknown" pre-eat;
##      eat() reveals the resolved effect, applies it, removes the fruit,
##      records stats; missing/rotted fruit refused.
##   D. Rot: exactly 1200 steps carried rots (1199 does not); rotted fruit
##      cannot be eaten; rotted counter tracks.
##   E. Spore infection -> gravebloom via the defeat flow with NO double
##      count: consume_defeat_infection() never bumps "gravebloom_grown";
##      infection is consumed on defeat; the single gs.on_player_defeat()
##      bump is the bloom. Second spore fruit replaces the infection.
##   F. Save/load round-trip through JSON: carried fruits (steps, lean_known,
##      effect, spore), infection, and stats survive; malformed payloads
##      refused.
##   G. ui_text.json "feeding" entries: story-lane verbatim lines (Sweet Potato
##      Creature, collab log 2026-10-05) — no [WIRING] markers remain; eat
##      prompt and all three Luna lean lines match the locked verbatim
##      exactly and substitute {fruit}; unknown label -> "".
##
## Run: ./Godot_v4.3-stable_linux.x86_64 --headless --path <project> -s res://scripts/feeding_loop_test.gd
## (Autoloads are not loaded under -s, so scripts are instantiated via load().)

const FeedingLoop = preload("res://scripts/feeding_loop.gd")
const UIText = preload("res://scripts/ui_text.gd")
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


## Value-compare two concoction dicts (Godot == on Dictionaries is
## reference-ish; compare the fields instead).
func _concoction_eq(a: Dictionary, b: Dictionary) -> bool:
	for k in ["host_plant", "name", "lean", "lean_known", "power_hidden", "spore", "steps_carried", "rotted"]:
		if str(a.get(k, "A")) != str(b.get(k, "B")):
			return false
	var ea: Dictionary = a.get("effect", {})
	var eb: Dictionary = b.get("effect", {})
	if str(ea.get("type", "")) != str(eb.get("type", "")):
		return false
	return int(ea.get("amount", -1)) == int(eb.get("amount", -2))


## Carry a fruit of a host, hunting seeds until predicate holds.
func _carry_seeded(gs: Node, host: String, pred: Callable) -> String:
	for seed in range(400):
		var f: Dictionary = FeedingLoop.pick_fruit(host, seed)
		if pred.call(f):
			return FeedingLoop.carry(gs, f)
	return ""


func _init() -> void:
	print("[feeding_loop_test] starting")
	_run.call_deferred()


func _run() -> void:
	_test_concoction()
	_test_luna_smell()
	_test_eat()
	_test_rot()
	_test_spore_defeat()
	_test_save_load()
	_test_ui_text()
	var total := _passes + _failures
	print("[TEST] feeding_loop: %d passed, %d failed (of %d)" % [_passes, _failures, total])
	if _failures > 0:
		quit(1)
	else:
		quit(0)


func _test_concoction() -> void:
	_check("5 seeded hosts", FeedingLoop.host_ids().size() == 5)
	var a: Dictionary = FeedingLoop.pick_fruit("gloomcap", 42)
	var b: Dictionary = FeedingLoop.pick_fruit("gloomcap", 42)
	_check("same host+seed identical concoction", _concoction_eq(a, b))
	var c: Dictionary = FeedingLoop.pick_fruit("gloomcap", 43)
	_check("different seed still valid", not c.is_empty() and str(c.get("host_plant", "")) == "gloomcap")
	_check("name derives from host", (str(a.get("name", ""))).find("Gloomcap") >= 0)
	_check("unknown host refused", FeedingLoop.pick_fruit("not_a_plant", 1).is_empty())
	_check("carry refuses empty fruit", FeedingLoop.carry(_make_gs(), {}) == "")
	_check("carry refuses unknown host", FeedingLoop.carry(_make_gs(), {"host_plant": "nope"}) == "")
	# Draws stay inside the host tables across many seeds.
	for host in FeedingLoop.host_ids():
		var ok := true
		for seed in range(60):
			var f: Dictionary = FeedingLoop.pick_fruit(str(host), seed)
			if not FeedingLoop.LEAN_TYPES.has(str(f.get("lean", ""))):
				ok = false
			var et := str((f.get("effect", {}) as Dictionary).get("type", ""))
			if et != "heal_vigor" and et != "grant_credits":
				ok = false
			if not (f.get("steps_carried", -1) is int) or int(f.get("steps_carried", -1)) != 0:
				ok = false
			if bool(f.get("rotted", true)):
				ok = false
			if not bool(f.get("power_hidden", false)):
				ok = false
		_check("host %s draws stay in tables" % str(host), ok)
	# Sequential instance ids from carry.
	var gs := _make_gs()
	var id1 := FeedingLoop.carry(gs, FeedingLoop.pick_fruit("gloomcap", 1))
	var id2 := FeedingLoop.carry(gs, FeedingLoop.pick_fruit("gloomcap", 2))
	_check("carry assigns ids", id1 == "fruit_gloomcap_1" and id2 == "fruit_gloomcap_2")
	_check("carried count 2", FeedingLoop.carried(gs).size() == 2)


func _test_luna_smell() -> void:
	var gs := _make_gs()
	var fid := FeedingLoop.carry(gs, FeedingLoop.pick_fruit("ember_vine", 7))
	var before: Dictionary = FeedingLoop.carried(gs)[0]
	_check("lean hidden pre-smell", str(FeedingLoop.describe(before).get("lean", "")) == "?")
	var res: Dictionary = FeedingLoop.luna_smell(gs, fid)
	_check("smell ok", bool(res.get("ok", false)))
	var lean := str(res.get("lean", ""))
	_check("lean in locked set", FeedingLoop.LEAN_TYPES.has(lean))
	_check("line non-empty", str(res.get("line", "")) != "")
	_check("line is verbatim, not a placeholder", str(res.get("line", "")).find("[WIRING") < 0)
	_check("line matches ui_text entry", str(res.get("line", "")) == UIText.feeding("luna_smell_" + lean))
	var after: Dictionary = FeedingLoop.carried(gs)[0]
	_check("lean revealed post-smell", str(FeedingLoop.describe(after).get("lean", "")) == lean)
	_check("smelled stat counted once", int((FeedingLoop.save_data(gs)["stats"] as Dictionary).get("smelled", 0)) == 1)
	var res2: Dictionary = FeedingLoop.luna_smell(gs, fid)
	_check("re-smell idempotent", bool(res2.get("ok", false)) and str(res2.get("lean", "")) == lean)
	_check("re-smell not recounted", int((FeedingLoop.save_data(gs)["stats"] as Dictionary).get("smelled", 0)) == 1)
	_check("smell unknown id fails", not bool((FeedingLoop.luna_smell(gs, "fruit_nope_9") as Dictionary).get("ok", true)))


func _test_eat() -> void:
	var gs := _make_gs()
	# Non-spore heal fruit (hunt seeds until one matches).
	var fid := _carry_seeded(gs, "mournroot", func(f: Dictionary) -> bool:
		return not bool(f.get("spore", true)) and str((f.get("effect", {}) as Dictionary).get("type", "")) == "heal_vigor")
	_check("seeded a heal fruit", fid != "")
	var fruit: Dictionary = FeedingLoop.carried(gs)[0]
	_check("power hidden pre-eat", str(FeedingLoop.describe(fruit).get("power", "")) == "unknown")
	_check("spore visible pre-eat", bool(FeedingLoop.describe(fruit).get("spore", true)) == false)
	# At full vigor the heal applies 0 but the eat still succeeds.
	var res: Dictionary = FeedingLoop.eat(gs, fid)
	_check("eat ok", bool(res.get("ok", false)))
	_check("effect revealed on eat", str((res.get("effect", {}) as Dictionary).get("type", "")) == "heal_vigor")
	_check("last_eaten recorded", str(((FeedingLoop.save_data(gs)["stats"] as Dictionary).get("last_eaten", {}) as Dictionary).get("type", "")) == "heal_vigor")
	_check("fruit removed from carried", FeedingLoop.carried(gs).is_empty())
	_check("eaten stat 1", int((FeedingLoop.save_data(gs)["stats"] as Dictionary).get("eaten", 0)) == 1)
	_check("no infection from clean fruit", not FeedingLoop.has_spore_infection(gs))
	# Heal applies when hurt.
	var gs2 := _make_gs()
	gs2.set_vigor(1)
	var heal_amt := 0
	var fid2 := _carry_seeded(gs2, "mournroot", func(f: Dictionary) -> bool:
		return not bool(f.get("spore", true)) and str((f.get("effect", {}) as Dictionary).get("type", "")) == "heal_vigor")
	var fr2: Dictionary = FeedingLoop.carried(gs2)[0]
	heal_amt = int((fr2.get("effect", {}) as Dictionary).get("amount", 0))
	var r2: Dictionary = FeedingLoop.eat(gs2, fid2)
	_check("hurt heal applies", int((r2.get("applied", {}) as Dictionary).get("healed", -1)) == mini(heal_amt, 2))
	_check("vigor capped at max", int((gs2.state["player"] as Dictionary).get("vigor", 0)) == 3)
	# Credits fruit.
	var gs3 := _make_gs()
	var before_credits: int = gs3.get_soul_credits()
	var fid3 := _carry_seeded(gs3, "hollow_reed", func(f: Dictionary) -> bool:
		return not bool(f.get("spore", true)) and str((f.get("effect", {}) as Dictionary).get("type", "")) == "grant_credits")
	var fr3: Dictionary = FeedingLoop.carried(gs3)[0]
	var cred_amt := int((fr3.get("effect", {}) as Dictionary).get("amount", 0))
	var r3: Dictionary = FeedingLoop.eat(gs3, fid3)
	_check("credits effect type", str((r3.get("effect", {}) as Dictionary).get("type", "")) == "grant_credits")
	_check("credits granted", gs3.get_soul_credits() == before_credits + cred_amt)
	_check("eat missing fruit fails", not bool((FeedingLoop.eat(gs3, "fruit_nope_9") as Dictionary).get("ok", true)))
	_check("eat missing reason", str((FeedingLoop.eat(gs3, "fruit_nope_9") as Dictionary).get("reason", "")) == "missing")


func _test_rot() -> void:
	var gs := _make_gs()
	var ids: Array = []
	for seed in [1, 2, 3]:
		ids.append(FeedingLoop.carry(gs, FeedingLoop.pick_fruit("gloomcap", seed)))
	var r := FeedingLoop.on_steps_taken(gs, 1199)
	_check("no rot at 1199", (r.get("rotted", []) as Array).is_empty())
	var c0: Dictionary = FeedingLoop.carried(gs)[0]
	_check("steps accumulate", int(c0.get("steps_carried", 0)) == 1199)
	_check("describe shows steps_until_rot", int(FeedingLoop.describe(c0).get("steps_until_rot", -1)) == 1)
	r = FeedingLoop.on_steps_taken(gs, 1)
	_check("all rot at exactly 1200", (r.get("rotted", []) as Array).size() == 3)
	_check("rotted flag set", bool((FeedingLoop.carried(gs)[0] as Dictionary).get("rotted", false)))
	_check("rotted stat 3", int((FeedingLoop.save_data(gs)["stats"] as Dictionary).get("rotted", 0)) == 3)
	var eat_res: Dictionary = FeedingLoop.eat(gs, str(ids[0]))
	_check("rotted fruit uneatable", not bool(eat_res.get("ok", true)) and str(eat_res.get("reason", "")) == "rotted")
	# Single jump straight to 1200.
	var gs2 := _make_gs()
	var fid := FeedingLoop.carry(gs2, FeedingLoop.pick_fruit("ember_vine", 5))
	r = FeedingLoop.on_steps_taken(gs2, 1200)
	_check("single 1200-step jump rots", (r.get("rotted", []) as Array) == [fid])
	# Zero steps: no-op.
	var gs3 := _make_gs()
	FeedingLoop.carry(gs3, FeedingLoop.pick_fruit("ember_vine", 5))
	r = FeedingLoop.on_steps_taken(gs3, 0)
	_check("zero steps no-op", (r.get("rotted", []) as Array).is_empty())


func _test_spore_defeat() -> void:
	# Infected defeat: infection consumed, spore bloom marked, the single
	# on_player_defeat() bump is the bloom (no double count).
	var gs := _make_gs()
	var fid := _carry_seeded(gs, "mournroot", func(f: Dictionary) -> bool:
		return bool(f.get("spore", false)))
	_check("seeded a spore fruit", fid != "")
	var fruit: Dictionary = FeedingLoop.carried(gs)[0]
	_check("spore visible pre-eat", bool(FeedingLoop.describe(fruit).get("spore", false)))
	var er: Dictionary = FeedingLoop.eat(gs, fid)
	_check("spore fruit infects", bool(er.get("infected", false)))
	_check("infection active", FeedingLoop.has_spore_infection(gs))
	_check("infection keeps host", str(FeedingLoop.get_infection(gs).get("host_plant", "")) == "mournroot")
	# Eating a second spore fruit replaces the infection (latest wins).
	var fid2 := _carry_seeded(gs, "gloomcap", func(f: Dictionary) -> bool:
		return bool(f.get("spore", false)))
	var er2: Dictionary = FeedingLoop.eat(gs, fid2)
	_check("second spore replaces infection", bool(er2.get("replaced_infection", false)))
	_check("infection host updated", str(FeedingLoop.get_infection(gs).get("host_plant", "")) == "gloomcap")
	# Defeat hook consumes; the counter is NOT touched by this system.
	_check("gravebloom_grown starts 0", gs.get_counter("gravebloom_grown") == 0)
	var dr: Dictionary = FeedingLoop.consume_defeat_infection(gs)
	_check("defeat hook reports spore bloom", bool(dr.get("spore_bloom", false)))
	_check("defeat hook reports host", str(dr.get("host_plant", "")) == "gloomcap")
	_check("infection consumed on defeat", not FeedingLoop.has_spore_infection(gs))
	_check("hook never bumps gravebloom_grown", gs.get_counter("gravebloom_grown") == 0)
	_check("spore defeat counted in feeding stats", int((FeedingLoop.save_data(gs)["stats"] as Dictionary).get("spore_defeats", 0)) == 1)
	# The canonical flow: hook first, then on_player_defeat() exactly once.
	gs.on_player_defeat()
	_check("one defeat = exactly one bloom (no double count)", gs.get_counter("gravebloom_grown") == 1)
	# Uninfected defeat: hook reports nothing, bloom still grows once.
	var gs2 := _make_gs()
	var dr2: Dictionary = FeedingLoop.consume_defeat_infection(gs2)
	_check("no infection no spore bloom", not bool(dr2.get("spore_bloom", true)))
	_check("hook alone grows nothing", gs2.get_counter("gravebloom_grown") == 0)
	gs2.on_player_defeat()
	_check("uninfected defeat still one bloom", gs2.get_counter("gravebloom_grown") == 1)
	# clear_spore_infection path.
	var gs3 := _make_gs()
	var fid3 := _carry_seeded(gs3, "mournroot", func(f: Dictionary) -> bool:
		return bool(f.get("spore", false)))
	FeedingLoop.eat(gs3, fid3)
	FeedingLoop.clear_spore_infection(gs3)
	_check("clear removes infection", not FeedingLoop.has_spore_infection(gs3))


func _test_save_load() -> void:
	var gs := _make_gs()
	var fid := FeedingLoop.carry(gs, FeedingLoop.pick_fruit("hollow_reed", 11))
	FeedingLoop.on_steps_taken(gs, 500)
	FeedingLoop.luna_smell(gs, fid)
	var spore_fid := _carry_seeded(gs, "mournroot", func(f: Dictionary) -> bool:
		return bool(f.get("spore", false)))
	FeedingLoop.eat(gs, spore_fid)
	var snap := JSON.stringify(FeedingLoop.save_data(gs))
	_check("save data serializes", snap != "")
	var back = JSON.parse_string(snap)
	_check("save data parses", back is Dictionary)
	var gs2 := _make_gs()
	_check("load_data accepts", FeedingLoop.load_data(gs2, back))
	_check("carried count survives", FeedingLoop.carried(gs2).size() == 1)
	var f2: Dictionary = FeedingLoop.carried(gs2)[0]
	_check("steps survive", int(f2.get("steps_carried", -1)) == 500)
	_check("lean_known survives", bool(f2.get("lean_known", false)))
	_check("effect survives", str((f2.get("effect", {}) as Dictionary).get("type", "")) != "")
	_check("infection survives", FeedingLoop.has_spore_infection(gs2))
	_check("stats survive", int((FeedingLoop.save_data(gs2)["stats"] as Dictionary).get("smelled", 0)) == 1)
	var gs3 := _make_gs()
	_check("load_data refuses empty", not FeedingLoop.load_data(gs3, {}))
	_check("load_data refuses bad carried", not FeedingLoop.load_data(gs3, {"carried": "nope", "infection": {}}))
	_check("failed load writes nothing", not (gs3.state as Dictionary).has("feeding"))
	# Lazy shape: a fresh new_game state has no feeding key until touched.
	var gs4 := _make_gs()
	(gs4.state as Dictionary).erase("feeding")
	_check("lazy shape creates carried", FeedingLoop.carried(gs4).is_empty())
	_check("lazy shape creates infection", not FeedingLoop.has_spore_infection(gs4))


func _test_ui_text() -> void:
	## Story-lane verbatim, locked by Sweet Potato Creature (collab log
	## 2026-10-05). Wiring side never paraphrases; these checks pin the
	## exact text so any drift fails loudly.
	const EXPECTED := {
		"eat_prompt": "Eat the {fruit}?",
		"luna_smell_necrolean": "Luna drifts close to the {fruit}. \"It leans toward Death. Not all the way \u2014 but the rot is in it.\"",
		"luna_smell_death": "Luna pulls back from the {fruit}. \"That one is Death through and through.\"",
		"luna_smell_eternilean": "Luna brightens around the {fruit}. \"Light. It leans toward the Light.\"",
		"rotted_note": "The {fruit} has rotted. Nothing left to eat.",
		"spore_note": "Something took root in you when you ate. It will remember where you fall.",
	}
	for label in EXPECTED.keys():
		var actual := UIText.feeding(label)
		_check("verbatim entry exists: %s" % label, actual != "")
		_check("verbatim matches story lock: %s" % label, actual == EXPECTED[label])
		_check("no [WIRING] marker remains: %s" % label, actual.find("[WIRING") < 0)
	_check("unknown label degrades to empty", UIText.feeding("no_such_line") == "")
	# {fruit} substitution through both accessor paths.
	var fruit := "Gloomcap Pale"
	_check("eat prompt substitutes fruit name", FeedingLoop.eat_prompt(fruit).find(fruit) >= 0)
	_check("eat prompt is the data string", FeedingLoop.eat_prompt(fruit) == UIText.feeding("eat_prompt").replace("{fruit}", fruit))
	for lean in FeedingLoop.LEAN_TYPES:
		var subbed := UIText.feeding("luna_smell_" + str(lean)).replace("{fruit}", fruit)
		_check("luna line substitutes fruit: %s" % str(lean), subbed.find(fruit) >= 0)
	_check("rotted note substitutes fruit", UIText.feeding("rotted_note").replace("{fruit}", fruit).find(fruit) >= 0)
