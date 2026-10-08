extends SceneTree
## Headless party-system test: starter grant, add/remove/swap, XP curve and
## level-ups (hand-computed), heal_all, save/load round-trip, BattleManager
## pulling the lead from the party, fainted-lead skip, all-fainted refusal.
## Run: ./Godot_v4.3-stable_linux.x86_64 --headless --path <project> -s res://scripts/party_test.gd
## Uses throwaway slot 97 so real saves are never touched.
## (Autoloads are not loaded under -s, so scripts are instantiated via load().)
##
## Hand-computed reference values (see data/*.json, battle_unit.gd):
##   xp_to_next(L) = round(20 * L^1.5):
##     L1=20, L2=57, L3=104, L4=160, L5=224, L6=294, L7=370.
##   snapling lv1 -> lv2 on 20 XP: max_hp 30 -> 32, atk 15 -> 16, def 7 -> 8
##     (BattleUnit.new("snapling", 2): atk round(15*1.08)=16, def
##     round(7*1.08)=8, hp round(30*1.08)=32).
##   snapling lv5 max_hp = round(30 * 1.32) = 40.
##   1000 XP on a fresh lv1: 20+57+104+160+224+294 = 859 spent -> lv7, 141 left.
##
## Tuning placeholders (not canon): XP_BASE 20, curve exponent 1.5.

const BattleUnit = preload("res://scripts/battle_unit.gd")

var _failures: Array[String] = []
var _nav: Array = []


func _check(name: String, cond: bool) -> void:
	if cond:
		print("  PASS: ", name)
	else:
		_failures.append(name)
		print("  FAIL: ", name)


func _make_gs():
	var party_script = load("res://scripts/party.gd")
	var ss = (load("res://scripts/save_system.gd")).new()
	root.add_child(ss)
	var ach = (load("res://scripts/achievements.gd")).new()
	root.add_child(ach)
	var gs = (load("res://scripts/game_state.gd")).new()
	gs.save_system = ss
	gs.achievements = ach
	root.add_child(gs)
	# NOTE: under -s, _ready() does not auto-fire for nodes added in _init().
	gs._ready()
	ach.game_state = gs
	return [gs, party_script]


func _init() -> void:
	print("=== PARTY SYSTEM TEST ===")
	var pair: Array = _make_gs()
	var gs = pair[0]
	var P = pair[1]

	# --- 1. new game grants the starter ---
	_check("party size 1 on new game", P.size(gs) == 1)
	var lead: Dictionary = P.get_entry(gs, 0)
	_check("starter is snapling", str(lead.get("creature_id", "")) == "snapling")
	_check("starter level 5", int(lead.get("level", 0)) == 5)
	_check("starter xp 0", int(lead.get("xp", -1)) == 0)
	_check("starter full hp 40", int(lead.get("current_hp", 0)) == 40)
	_check("starter has abilities", (lead.get("ability_ids", []) as Array).size() > 0)
	_check("starter nickname stored", lead.has("nickname"))

	# --- 2. add up to 6; 7th fails; unknown id fails ---
	_check("add bellowscap", P.add_creature(gs, "bellowscap", 3))
	_check("add siltmaw", P.add_creature(gs, "siltmaw", 4))
	_check("add gravebind", P.add_creature(gs, "gravebind", 2))
	_check("add thornchoir", P.add_creature(gs, "thornchoir", 6))
	_check("add bellmaw", P.add_creature(gs, "bellmaw", 12))
	_check("party size 6", P.size(gs) == 6)
	_check("7th add refused", not P.add_creature(gs, "snapling", 1))
	_check("size still 6", P.size(gs) == 6)
	_check("unknown creature refused", not P.add_creature(gs, "nope", 1))

	# --- 3. swap reorders ---
	_check("swap 0/5", P.swap(gs, 0, 5))
	_check("index 0 now bellmaw", str(P.get_entry(gs, 0).get("creature_id", "")) == "bellmaw")
	_check("index 5 now snapling", str(P.get_entry(gs, 5).get("creature_id", "")) == "snapling")
	_check("swap invalid refused", not P.swap(gs, 0, 9) and not P.swap(gs, -1, 0))

	# --- 4. remove ---
	_check("remove invalid refused", not P.remove_creature(gs, 9))
	_check("remove index 5", P.remove_creature(gs, 5))
	_check("size 5 after remove", P.size(gs) == 5)

	# --- 5. XP: single level-up, hand-computed ---
	var pair2: Array = _make_gs()
	var gs2 = pair2[0]
	var P2 = pair2[1]
	P2.remove_creature(gs2, 0)  # drop the lv5 starter
	_check("add snapling lv1", P2.add_creature(gs2, "snapling", 1))
	_check("xp_to_next(1) == 20", P2.xp_to_next(1) == 20)
	_check("xp_to_next(5) == 224", P2.xp_to_next(5) == 224)
	P2.set_hp(gs2, 0, 20)  # damage it first: level-up should preserve damage
	var ups: Array = P2.gain_xp(gs2, 0, 20)
	_check("one level-up", ups == [2])
	var e: Dictionary = P2.get_entry(gs2, 0)
	_check("now level 2", int(e.get("level", 0)) == 2)
	_check("xp remainder 0", int(e.get("xp", -1)) == 0)
	_check("hp lifted by max delta 20->22", int(e.get("current_hp", 0)) == 22)
	var ref = BattleUnit.new("snapling", 2)
	_check("lv2 stats atk 16", ref.attack == 16)
	_check("lv2 stats def 8", ref.defense == 8)
	_check("lv2 stats max_hp 32", ref.max_hp == 32)
	_check("entry max matches unit", P2.max_hp_for(e) == 32)
	# XP on a fainted member: levels rise, HP stays 0.
	P2.set_hp(gs2, 0, 0)
	var ups2: Array = P2.gain_xp(gs2, 0, 57)
	_check("fainted levels to 3", ups2 == [3] and int(P2.get_entry(gs2, 0).get("level", 0)) == 3)
	_check("fainted stays at 0 hp", int(P2.get_entry(gs2, 0).get("current_hp", -1)) == 0)
	# Invalid / non-positive XP is a no-op.
	_check("xp invalid index", P2.gain_xp(gs2, 9, 100).is_empty())
	_check("xp zero amount", P2.gain_xp(gs2, 0, 0).is_empty())

	# --- 6. XP: multi-level gain, hand-computed ---
	var pair3: Array = _make_gs()
	var gs3 = pair3[0]
	var P3 = pair3[1]
	P3.remove_creature(gs3, 0)
	P3.add_creature(gs3, "snapling", 1)
	var ups3: Array = P3.gain_xp(gs3, 0, 1000)
	_check("1000 xp -> lv7", ups3 == [2, 3, 4, 5, 6, 7])
	var e3: Dictionary = P3.get_entry(gs3, 0)
	_check("final level 7", int(e3.get("level", 0)) == 7)
	_check("final xp 141", int(e3.get("xp", -1)) == 141)
	_check("full hp at lv7", int(e3.get("current_hp", 0)) == P3.max_hp_for(e3))

	# --- 7. heal_all ---
	P3.set_hp(gs3, 0, 1)
	P3.add_creature(gs3, "bellowscap", 2)
	P3.set_hp(gs3, 1, 3)
	P3.heal_all(gs3)
	_check("heal_all restores 0", int(P3.get_entry(gs3, 0).get("current_hp", 0)) == P3.max_hp_for(P3.get_entry(gs3, 0)))
	_check("heal_all restores 1", int(P3.get_entry(gs3, 1).get("current_hp", 0)) == P3.max_hp_for(P3.get_entry(gs3, 1)))

	# --- 8. save -> load round-trip ---
	var nick: Dictionary = P3.get_entry(gs3, 0)
	nick["nickname"] = "Buddy"
	P3.set_hp(gs3, 0, 12)
	_check("save_to_slot(97)", gs3.save_to_slot(97))
	P3.remove_creature(gs3, 1)
	P3.set_hp(gs3, 0, 1)
	_check("load_from_slot(97)", gs3.load_from_slot(97))
	_check("party size restored", P3.size(gs3) == 2)
	var r0: Dictionary = P3.get_entry(gs3, 0)
	_check("entry 0 id/level/xp", str(r0.get("creature_id", "")) == "snapling" and int(r0.get("level", 0)) == 7 and int(r0.get("xp", 0)) == 141)
	_check("entry 0 hp restored", int(r0.get("current_hp", 0)) == 12)
	_check("nickname restored", str(r0.get("nickname", "")) == "Buddy")
	_check("entry 1 restored", str(P3.get_entry(gs3, 1).get("creature_id", "")) == "bellowscap")
	gs3.save_system.delete_save(97)

	# --- 9. BattleManager pulls the lead from the party ---
	var bm = (load("res://scripts/battle_manager.gd")).new()
	bm.game_state = gs  # gs party: [bellmaw lv12, bellowscap, siltmaw, gravebind, thornchoir]
	bm.scene_changer = _nav.append
	root.add_child(bm)
	_check("wild start ok", bm.start_wild_battle("siltmaw", 2, "c1", Vector2(1, 2)))
	_check("pending uses party lead id", str(bm.pending.get("player_creature_id", "")) == "bellmaw")
	_check("pending uses party lead level", int(bm.pending.get("player_level", 0)) == 12)
	_check("pending party index 0", int(bm.pending.get("player_party_index", -1)) == 0)
	_check("pending carries lead hp", int(bm.pending.get("player_hp", -1)) == int(P.get_entry(gs, 0).get("current_hp", -2)))
	bm.clear_pending()

	# --- 10. fainted lead is skipped, next conscious steps up ---
	P.set_hp(gs, 0, 0)
	_nav.clear()
	_check("start with fainted lead", bm.start_wild_battle("siltmaw", 2, "c1", Vector2.ZERO))
	_check("skips to index 1", int(bm.pending.get("player_party_index", -1)) == 1)
	_check("uses index 1 creature", str(bm.pending.get("player_creature_id", "")) == str(P.get_entry(gs, 1).get("creature_id", "")))
	bm.clear_pending()

	# --- 11. all fainted -> battle refused ---
	for i in P.size(gs):
		P.set_hp(gs, i, 0)
	_nav.clear()
	_check("all fainted refuses start", not bm.start_wild_battle("siltmaw", 2, "c1", Vector2.ZERO))
	_check("nothing pending", bm.pending.is_empty())
	_check("no scene change queued", _nav.is_empty())
	bm.queue_free()

	print("=== TEST DONE: %d failure(s) ===" % _failures.size())
	if not _failures.is_empty():
		print("failures: ", _failures)
	quit(1 if not _failures.is_empty() else 0)
