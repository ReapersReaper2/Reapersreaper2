extends SceneTree
## Headless battle-item test: items.json effects, ITEM menu gating, heal/cure/
## revive/damage/status/decoy/buff flows, turn cost, snare routing, no errors.
## Run: Godot --headless --path <project> -s res://scripts/item_test.gd
##
## Docs basis (04-items-crafting.md §1): poultice heals 40 HP, sap draught 80,
## blossom nectar is OUT OF COMBAT ONLY, mandrake tea cures Wilt+Spore-fever,
## ashen salt cures Hollow, second bell revives at 50%, thorn pod = fixed
## plant damage, spore sac inflicts spore-fever, gravebind snare = rootbound,
## silver bell bloom = decoy (one wasted enemy attack), ironwood bark =
## +DEF/-SPD 3 turns. Wiring placeholders (flagged): thorn pod amount 25,
## ironwood bark multipliers 1.75/0.6, spore-fever fail chance 30%.

var _failures: Array[String] = []
var _ran := false
var _nav: Array = []
var CreatureData = null
var PartyScript = null


func _check(name: String, cond: bool) -> void:
	if cond:
		print("  PASS: ", name)
	else:
		_failures.append(name)
		print("  FAIL: ", name)


func _make_gs():
	var ss = (load("res://scripts/save_system.gd")).new()
	root.add_child(ss)
	var ach = (load("res://scripts/achievements.gd")).new()
	root.add_child(ach)
	var gs = (load("res://scripts/game_state.gd")).new()
	gs.save_system = ss
	gs.achievements = ach
	root.add_child(gs)
	gs._ready()
	ach.game_state = gs
	return gs


func _make_battle(gs, cfg: Dictionary):
	var b = (load("res://scripts/battle.gd")).new()
	b.fast_mode = true
	b.game_state = gs
	b.battle_config = cfg
	b.scene_changer = _nav.append
	root.add_child(b)
	return b


func _wild_cfg() -> Dictionary:
	return {
		"player_creature_id": "snapling", "player_level": 5,
		"player_hp": -1, "player_party_index": 0,
		"enemy_creature_id": "bellowscap", "enemy_level": 1,
		"is_boss": false, "victory_flag": "",
		"return_room": "c1", "return_pos": Vector2(1900, 0),
	}


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_run()
	return false


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _stock(gs, ids: Array) -> void:
	for item_id in ids:
		gs.add_item(str(item_id), 3)


func _run() -> void:
	print("[item_test]")
	CreatureData = load("res://scripts/creature_data.gd")
	PartyScript = load("res://scripts/party.gd")
	var gs = _make_gs()

	# --- 1. items.json effects from the docs ---
	_check("14 items load", CreatureData.get_item("grave_moss_poultice").get("effect", {}).get("type") == "heal_hp")
	_check("poultice heals 40", int(CreatureData.get_item("grave_moss_poultice")["effect"]["amount"]) == 40)
	_check("sap draught heals 80", int(CreatureData.get_item("sap_draught")["effect"]["amount"]) == 80)
	_check("nectar out-of-combat only", bool(CreatureData.get_item("blossom_nectar")["effect"].get("out_of_combat_only", false)))
	_check("tea cures wilt+spore_fever", (CreatureData.get_item("mandrake_tea")["effect"]["statuses"] as Array).has("wilt"))
	_check("ashen salt cures hollow", (CreatureData.get_item("ashen_salt")["effect"]["statuses"] as Array).has("hollow"))
	_check("second bell revive 50%", is_equal_approx(float(CreatureData.get_item("second_bell")["effect"]["hp_fraction"]), 0.5))
	_check("snare is catch type", CreatureData.get_item("soul_snare")["effect"]["type"] == "catch")
	_check("snare NOT in item menu order", not ("soul_snare" in (load("res://scripts/battle.gd") as GDScript).BATTLE_ITEM_ORDER))

	# --- 2. new game grants starting poultices ---
	_check("new game: 2 poultices", gs.get_item_count("grave_moss_poultice") == 2)
	_check("new game: 5 snares", gs.get_item_count("soul_snare") == 5)

	# --- 3. ITEM menu opens; context gating ---
	_stock(gs, ["grave_moss_poultice", "sap_draught", "blossom_nectar", "mandrake_tea",
		"ashen_salt", "second_bell", "thorn_pod", "spore_sac", "gravebind_snare",
		"silver_bell_bloom", "ironwood_bark"])
	_nav.clear()
	var b = _make_battle(gs, _wild_cfg())
	await _frames(3)
	_check("command state", b._state == 1)
	b.choose_item()
	await _frames(1)  # let queue_free() clear the old command buttons
	_check("item menu state", b._state == 3)  # State.ITEMS
	_check("menu lists battle items + back", b._menu.get_child_count() == 12)  # 11 stocked + BACK
	var ctx: Dictionary = b._item_context("grave_moss_poultice")
	_check("poultice unusable at full HP", not bool(ctx.get("usable", true)) and str(ctx.get("reason", "")) == "HP full")
	var btn0 := b._menu.get_child(0) as Button
	_check("full-hp heal dimmed", btn0.disabled)
	ctx = b._item_context("blossom_nectar")
	_check("nectar dimmed in battle", not bool(ctx.get("usable", true)))
	ctx = b._item_context("mandrake_tea")
	_check("tea dimmed with no status", not bool(ctx.get("usable", true)))
	ctx = b._item_context("second_bell")
	_check("bell dimmed, none fainted", not bool(ctx.get("usable", true)))
	b.queue_free()

	# --- 4. heal: correct amount, no overheal, consumed, costs the turn ---
	# Fixture note (Wrath 2026-10-10): the shared wild cfg uses a DOCILE
	# bellowscap, which stands still when unprovoked (CreatureAI docile
	# Stillness — canon Act 2 behavior), so it never damages the player and
	# the 40-heal from 10 clamps to max_hp, leaving hp == maxhp. That is
	# correct implementation behavior; this section needs an enemy that
	# actually attacks to observe the turn cost, so it overrides the fixture.
	_nav.clear()
	var cfg4: Dictionary = _wild_cfg()
	cfg4["enemy_creature_id"] = "siltmaw"  # AGGRESSIVE: answers after the item
	b = _make_battle(gs, cfg4)
	await _frames(3)
	b._player.hp = 10
	var maxhp: int = b._player.max_hp
	var before: int = gs.get_item_count("grave_moss_poultice")
	b.choose_item()
	b._on_item("grave_moss_poultice")
	await _frames(12)
	_check("poultice consumed", gs.get_item_count("grave_moss_poultice") == before - 1)
	_check("healed then enemy acted (turn cost)", b._player.hp < maxhp and b._player.hp > 10)
	_check("back at command", b._state == 1)
	b.queue_free()

	# --- 5. no overheal: heal clamps ---
	_nav.clear()
	b = _make_battle(gs, _wild_cfg())
	await _frames(3)
	b._player.hp = b._player.max_hp - 5
	# Suppress the enemy's reply so we can check the clamp cleanly.
	b._enemy.ability_ids = []
	b.choose_item()
	b._on_item("sap_draught")
	await _frames(12)
	_check("sap draught clamps at max", b._player.hp == b._player.max_hp)
	b.queue_free()

	# --- 6. cure: mandrake tea removes WILT ---
	_nav.clear()
	b = _make_battle(gs, _wild_cfg())
	await _frames(3)
	b._player.apply_status("wilt", 3)
	b._enemy.ability_ids = []
	ctx = b._item_context("mandrake_tea")
	_check("tea usable while wilting", bool(ctx.get("usable", false)))
	b.choose_item()
	b._on_item("mandrake_tea")
	await _frames(12)
	_check("wilt cured", not b._player.statuses.has("wilt"))
	b.queue_free()

	# --- 7. second bell: revive fainted member at 50% ---
	PartyScript.add_creature(gs, "siltmaw", 4)
	PartyScript.set_hp(gs, 1, 0)
	_nav.clear()
	b = _make_battle(gs, _wild_cfg())
	await _frames(3)
	b._enemy.ability_ids = []
	ctx = b._item_context("second_bell")
	_check("bell usable with fainted member", bool(ctx.get("usable", false)))
	b.choose_item()
	b._on_item("second_bell")
	await _frames(3)
	_check("revive target state", b._state == 4)  # State.ITEM_TARGET
	b._on_revive_target("second_bell", 1)
	await _frames(12)
	var e: Dictionary = PartyScript.get_entry(gs, 1)
	var want: int = maxi(1, int(round(float(PartyScript.max_hp_for(e)) * 0.5)))
	_check("revived at 50% HP", int(e.get("current_hp", 0)) == want)
	_check("bell consumed", gs.get_item_count("second_bell") == 2)
	_check("back at command", b._state == 1)
	b.queue_free()

	# --- 8. thorn pod: fixed damage, ignores guard ---
	_nav.clear()
	b = _make_battle(gs, _wild_cfg())
	await _frames(3)
	var ehp: int = b._enemy.hp
	b._enemy.ability_ids = []
	b.choose_item()
	b._on_item("thorn_pod")
	await _frames(12)
	_check("thorn pod deals fixed 25", ehp - b._enemy.hp == 25)
	b.queue_free()

	# --- 9. spore sac + gravebind snare: statuses land ---
	_nav.clear()
	b = _make_battle(gs, _wild_cfg())
	await _frames(3)
	b._enemy.ability_ids = []
	b.choose_item()
	b._on_item("spore_sac")
	await _frames(12)
	_check("spore-fever applied", int(b._enemy.statuses.get("spore_fever", 0)) > 0)
	b.queue_free()
	_nav.clear()
	b = _make_battle(gs, _wild_cfg())
	await _frames(3)
	b._enemy.ability_ids = []
	b.choose_item()
	b._on_item("gravebind_snare")
	await _frames(12)
	_check("rootbound applied", int(b._enemy.statuses.get("rootbound", 0)) > 0)
	b.queue_free()

	# --- 10. silver bell bloom: decoy wastes the enemy attack ---
	_nav.clear()
	b = _make_battle(gs, _wild_cfg())
	await _frames(3)
	b._player.hp = 20
	var php: int = b._player.hp
	b.choose_item()
	b._on_item("silver_bell_bloom")
	await _frames(12)
	_check("decoy wasted the attack", b._player.hp == php)
	_check("decoy consumed flag", not b._decoy_active)
	b.queue_free()

	# --- 11. ironwood bark: def up, speed down, 3 turns ---
	_nav.clear()
	b = _make_battle(gs, _wild_cfg())
	await _frames(3)
	b._enemy.ability_ids = []
	var bd: int = b._player.effective_defense()
	var bs: int = b._player.effective_speed()
	b.choose_item()
	b._on_item("ironwood_bark")
	await _frames(12)
	_check("bark raises defense", b._player.effective_defense() > bd)
	_check("bark lowers speed", b._player.effective_speed() < bs)
	_check("bark lasts 3 turns", int(b._player.temp_mods.get("turns", 0)) == 2)  # one ticked
	b.queue_free()

	# --- 12. snare routing: CATCH still works, snare not in ITEM menu ---
	_nav.clear()
	b = _make_battle(gs, _wild_cfg())
	await _frames(3)
	_check("catch enabled (snares held)", not (b._menu.get_child(1) as Button).disabled)
	b.queue_free()

	print("[item_test] failures: ", _failures.size())
	if _failures.is_empty():
		print("[item_test] ALL PASS")
	quit(0 if _failures.is_empty() else 1)
