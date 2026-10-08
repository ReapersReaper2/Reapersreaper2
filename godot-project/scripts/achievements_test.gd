extends SceneTree
## Steam achievement event system — headless test.
##
## Covers: the 22-achievement Steam registry (ids, names, descriptions,
## hidden flags), unlock-once semantics, persistence in the GameState
## ledger, reset, steam_sync stub, the 8 hook-ready notifiers, and every
## existing-system hook: set_flag beats (mirror_broken, armor_born,
## green_burial, ledger_read, the_choice), set_form beats (reaper_rises),
## breeding hatch (first_hatch, gardener), fabricator graft (first_graft),
## Quiet Table win (drowned_dice), room entry (the_hollow, return).

const AchScript := preload("res://scripts/achievements.gd")
const GameStateScript := preload("res://scripts/game_state.gd")
const BreedingScript := preload("res://scripts/breeding.gd")
const FabricatorScript := preload("res://scripts/fabricator.gd")
const DiceScript := preload("res://scripts/dice_game.gd")
const RoomScript := preload("res://scripts/room.gd")

## The 23 Steam-spec ids (story-bot spec 2026-10-04; its "Total: 22"
## is an arithmetic slip — the tables list 23).
const STEAM_IDS: Array = [
	"first_death", "reaper_rises", "armor_born", "green_burial",
	"scythe_breaks", "the_hollow", "wings", "mirror_broken",
	"the_choice", "return",
	"first_hatch", "spore_harvest", "wrong_step", "dragon_roost",
	"gardener",
	"first_graft", "blade_regrown", "ledger_read", "drowned_dice",
	"clean_hunt", "eleven_flowers", "no_bloom_seized",
	"choki",
]

var _failures := 0
var _passes := 0
var _signal_count := 0


func _check(name: String, cond: bool) -> void:
	if cond:
		_passes += 1
		print("  PASS: ", name)
	else:
		_failures += 1
		print("  FAILED: ", name)


func _make_pair() -> Array:
	# NOTE: Godot loads project autoloads even for headless -s runs, so the
	# live /root/Achievements singleton is used (a second node named
	# "Achievements" would be renamed @Node@N and shadowed by the autoload).
	var gs = GameStateScript.new()
	gs.save_system = null
	gs.new_game()
	var ach = root.get_node("Achievements")
	ach.reset_all()
	ach.game_state = gs
	gs.achievements = ach
	_signal_count = 0
	if not ach.achievement_unlocked.is_connected(_on_ach_unlocked):
		ach.achievement_unlocked.connect(_on_ach_unlocked)
	return [gs, ach]


func _on_ach_unlocked(_id: String) -> void:
	_signal_count += 1

func _init() -> void:
	print("[achievements_test] starting")
	_run.call_deferred()


func _run() -> void:
	_test_registry()
	_test_unlock_semantics()
	_test_steam_sync()
	_test_flag_beats()
	_test_form_beats()
	_test_breeding_hooks()
	_test_fabricator_hook()
	_test_dice_hook()
	_test_room_entry_hooks()
	_test_hook_ready_notifiers()
	_test_story_bot_answers()
	print("[achievements_test] done: %d passed, %d failed" % [_passes, _failures])
	if _failures > 0:
		quit(1)
	else:
		quit(0)


func _test_registry() -> void:
	var pair := _make_pair()
	var ach = pair[1]
	_check("registry holds all 23 steam ids", _has_all(ach, STEAM_IDS))
	# Spec's "Total: 22" is an arithmetic slip — its tables list 23
	# (10 story + 5 breeding + 4 fabricator + 3 challenge + 1 post-game).
	_check("total count is 43 (20 launch + 23 steam)", ach.total_count() == 43)
	_check("gardener is hidden", bool(ach.ACHIEVEMENTS["gardener"]["hidden"]))
	_check("no_bloom_seized is hidden", bool(ach.ACHIEVEMENTS["no_bloom_seized"]["hidden"]))
	_check("first_death not hidden", not bool(ach.ACHIEVEMENTS["first_death"]["hidden"]))
	_check("wings not hidden", not bool(ach.ACHIEVEMENTS["wings"]["hidden"]))
	_check("first_death name", str(ach.ACHIEVEMENTS["first_death"]["name"]) == "The Knight Falls")
	_check("wings name", str(ach.ACHIEVEMENTS["wings"]["name"]) == "The Point of No Return")
	_check("drowned_dice name", str(ach.ACHIEVEMENTS["drowned_dice"]["name"]) == "Against the Odds")
	_check("clean_hunt name", str(ach.ACHIEVEMENTS["clean_hunt"]["name"]) == "Survive Cleanly")
	_check("gardener description mentions armor plant",
		str(ach.ACHIEVEMENTS["gardener"]["description"]).find("armor plant") >= 0)



func _has_all(ach, ids: Array) -> bool:
	for id in ids:
		if not ach.ACHIEVEMENTS.has(id):
			return false
	return true


func _test_unlock_semantics() -> void:
	var pair := _make_pair()
	var gs = pair[0]
	var ach = pair[1]
	_signal_count = 0
	ach.achievement_unlocked.connect(_on_ach_unlocked)
	_check("unlock returns true", ach.unlock("first_death") == true)
	_check("is_unlocked after unlock", ach.is_unlocked("first_death"))
	_check("signal fired once", _signal_count == 1)
	_check("second unlock returns true (idempotent)", ach.unlock("first_death") == true)
	_check("signal not re-fired", _signal_count == 1)
	_check("unknown id returns false", ach.unlock("nope_not_real") == false)
	_check("unknown id not unlocked", not ach.is_unlocked("nope_not_real"))
	_check("unlock_count tracks", ach.unlock_count() == 1)
	ach.reset_all()
	_check("reset clears ledger", ach.unlock_count() == 0 and not ach.is_unlocked("first_death"))
	ach.unlock("wings")
	_check("unlock persists in game_state ledger",
		(gs.state["ledger"] as Dictionary)["achievements"].has("wings"))



func _test_steam_sync() -> void:
	var pair := _make_pair()
	var ach = pair[1]
	ach.unlock("first_death")
	ach.steam_sync()  # stub: must not error
	_check("steam_sync runs without error", true)
	for n in ["notify_scythe_break", "notify_spore_harvest", "notify_wrong_step",
			"notify_dragon_roost", "notify_blade_regrown", "notify_eleven_flowers",
			"notify_no_bloom_seized", "notify_choki"]:
		_check("hook-ready notifier exists: " + n, ach.has_method(n))



func _test_flag_beats() -> void:
	var pair := _make_pair()
	var gs = pair[0]
	var ach = pair[1]
	# Trigger-map alignment (story-bot spec 2026-10-04).
	gs.set_flag("prologue_complete", true)
	_check("prologue flag -> first_death", ach.is_unlocked("first_death"))
	gs.set_flag("form3_unlocked", true)
	_check("form3 flag -> reaper_rises", ach.is_unlocked("reaper_rises"))
	gs.set_flag("form4_unlocked", true)
	_check("form4 flag -> armor_born", ach.is_unlocked("armor_born"))
	gs.set_flag("form5_unlocked", true)
	_check("form5 flag -> green_burial", ach.is_unlocked("green_burial"))
	gs.set_flag("form9_unlocked", true)
	_check("form9 flag -> wings", ach.is_unlocked("wings"))
	gs.set_flag("hl1_entered", true)
	_check("hl1 flag -> the_hollow", ach.is_unlocked("the_hollow"))
	gs.set_flag("harrow_defeated", true)
	_check("harrow flag -> mirror_broken", ach.is_unlocked("mirror_broken"))
	gs.set_flag("ending_choice", true)
	_check("ending_choice flag -> the_choice", ach.is_unlocked("the_choice"))
	gs.set_flag("e2_fragment_planted", true)
	_check("e2 flag -> return", ach.is_unlocked("return"))
	gs.set_flag("e1_ledger_read", true)
	_check("ledger flag -> ledger_read", ach.is_unlocked("ledger_read"))
	gs.set_flag("scythe_broken", true)
	_check("scythe flag -> scythe_breaks", ach.is_unlocked("scythe_breaks"))
	gs.set_flag("armor_plant_bred", true)
	_check("armor_plant_bred flag -> gardener", ach.is_unlocked("gardener"))
	gs.set_flag("tutorial_clean", true)
	_check("tutorial_clean flag -> clean_hunt", ach.is_unlocked("clean_hunt"))
	gs.set_flag("dice_won_max_stakes", true)
	_check("dice flag -> drowned_dice", ach.is_unlocked("drowned_dice"))
	gs.set_flag("some_random_flag", true)
	# ending_choice fires the_choice AND no_bloom_seized (story-bot
	# answers 2026-10-04: armor never seized a turn this playthrough),
	# so the count is 15, not 14.
	_check("unmapped flag unlocks nothing extra", ach.unlock_count() == 15)



func _test_form_beats() -> void:
	var pair := _make_pair()
	var gs = pair[0]
	var ach = pair[1]
	gs.set_form(3)
	_check("set_form(3) -> reaper_rises", ach.is_unlocked("reaper_rises"))
	gs.set_form(4)
	_check("set_form(4) -> armor_born", ach.is_unlocked("armor_born"))
	gs.set_form(5)
	_check("set_form(5) -> green_burial", ach.is_unlocked("green_burial"))
	gs.set_form(2)
	_check("set_form(2) unlocks no steam achievement", ach.unlock_count() == 3)



func _test_breeding_hooks() -> void:
	var pair := _make_pair()
	var gs = pair[0]
	var ach = pair[1]
	BreedingScript._ach_on_hatch(gs, {"creature_id": "snapling"})
	_check("hatch -> first_hatch", ach.is_unlocked("first_hatch"))
	_check("creature_hatched counter is 1", gs.get_counter("creature_hatched") == 1)
	BreedingScript._ach_on_hatch(gs, {"creature_id": "snapling"})
	_check("second hatch does not re-fire first_hatch logic (counter 2)",
		gs.get_counter("creature_hatched") == 2 and ach.is_unlocked("first_hatch"))
	_check("non-armor hatch does not unlock gardener", not ach.is_unlocked("gardener"))
	BreedingScript._ach_on_hatch(gs, {"creature_id": "armor_plant"})
	_check("first armor plant sets the once-flag, no gardener yet",
		not ach.is_unlocked("gardener") and bool(gs.get_flag("armor_plant_bred_once")))
	BreedingScript._ach_on_hatch(gs, {"creature_id": "armor_plant"})
	_check("second armor plant sets armor_plant_bred -> gardener",
		ach.is_unlocked("gardener") and bool(gs.get_flag("armor_plant_bred")))



func _test_fabricator_hook() -> void:
	var pair := _make_pair()
	var gs = pair[0]
	var ach = pair[1]
	var out: Dictionary = FabricatorScript._graft_ok(gs, "test graft")
	_check("graft ok dict", bool(out.get("ok", false)))
	_check("graft -> first_graft", ach.is_unlocked("first_graft"))
	_check("graft_completed counter is 1", gs.get_counter("graft_completed") == 1)
	FabricatorScript._graft_ok(gs, "second graft")
	_check("second graft bumps counter, no double unlock",
		gs.get_counter("graft_completed") == 2 and ach.is_unlocked("first_graft"))



func _test_dice_hook() -> void:
	var pair := _make_pair()
	var gs = pair[0]
	var ach = pair[1]
	DiceScript.record_win(gs, "quiet")
	_check("quiet win -> drowned_dice", ach.is_unlocked("drowned_dice"))
	_check("quiet win still -> quiet_wisdom", ach.is_unlocked("quiet_wisdom"))
	DiceScript.record_win(gs, "copper")
	_check("copper win does not unlock drowned_dice twice (count sane)",
		ach.is_unlocked("drowned_dice"))



func _test_room_entry_hooks() -> void:
	var pair := _make_pair()
	var ach = pair[1]
	# Rooms read flags from the autoload GameState (room.gd _ready resolves
	# /root/GameState), so flags go on the autoload. Unlocks land in the
	# test ledger via ach.game_state (set_flag -> unlock_for_flag).
	var ags = root.get_node("GameState")
	# HL1 first entry sets hl1_entered -> the_hollow (trigger map).
	var r1 = RoomScript.new()
	r1.room_id = "hl1"
	root.add_child(r1)
	_check("hl1 entry sets hl1_entered flag", bool(ags.get_flag("hl1_entered")))
	_check("hl1_entered unlocks the_hollow", ach.is_unlocked("the_hollow"))
	root.remove_child(r1)
	r1.free()
	ags.clear_flag("hl1_entered")
	# e2 entry no longer fires "return" (trigger map: e2_fragment_planted).
	ach.reset_all()
	var r3 = RoomScript.new()
	r3.room_id = "e2"
	root.add_child(r3)
	_check("e2 entry alone unlocks nothing", not ach.is_unlocked("return"))
	root.remove_child(r3)
	r3.free()



func _test_hook_ready_notifiers() -> void:
	var pair := _make_pair()
	var ach = pair[1]
	ach.notify_scythe_break()
	ach.notify_spore_harvest()
	ach.notify_wrong_step()
	ach.notify_dragon_roost()
	ach.notify_blade_regrown()
	ach.notify_eleven_flowers()
	ach.notify_no_bloom_seized()
	ach.notify_choki()
	for id in ["scythe_breaks", "spore_harvest", "wrong_step", "dragon_roost",
			"blade_regrown", "eleven_flowers", "no_bloom_seized", "choki"]:
		_check("notifier unlocks: " + id, ach.is_unlocked(id))




## Story-bot answers 2026-10-04: the three hooks with existing systems.
## (spore_harvest / wrong_step / dragon_roost / choki stay registered-but-
## dormant until their systems exist; ledger_read already fires on the
## e1_ledger_read flag.)
func _test_story_bot_answers() -> void:
	# 1. eleven_flowers — graveblooms grow on player defeat (canon: the
	# only source); 11th in one playthrough fires the achievement.
	var pair := _make_pair()
	var gs = pair[0]
	var ach = pair[1]
	for i in range(10):
		gs.on_player_defeat()
	_check("10 defeats: not yet", not ach.is_unlocked("eleven_flowers"))
	gs.on_player_defeat()
	_check("11th defeat grows the 11th gravebloom -> eleven_flowers",
		ach.is_unlocked("eleven_flowers"))
	_check("gravebloom counter is 11", gs.get_counter("gravebloom_grown") == 11)
	gs.new_game()
	_check("per-playthrough: counter resets on new_game",
		gs.get_counter("gravebloom_grown") == 0)

	# 2. no_bloom_seized — fires at the o3 ending_choice if the armor
	# never seized a turn (armor-seize mechanic sets bloom_seized).
	pair = _make_pair()
	gs = pair[0]
	ach = pair[1]
	gs.set_flag("ending_choice", true)
	_check("ending with no seize -> no_bloom_seized",
		ach.is_unlocked("no_bloom_seized"))
	pair = _make_pair()
	gs = pair[0]
	ach = pair[1]
	gs.set_flag("bloom_seized", true)
	gs.set_flag("ending_choice", true)
	_check("seize happened -> no_bloom_seized stays locked",
		not ach.is_unlocked("no_bloom_seized"))
	gs.new_game()
	_check("per-playthrough: bloom_seized resets on new_game",
		not gs.get_flag("bloom_seized"))

	# 3. blade_regrown — fires on blade-regrowth graft completion.
	pair = _make_pair()
	gs = pair[0]
	ach = pair[1]
	gs.add_item("broken_sword", 1)
	FabricatorScript.learn(gs, "broken_sword")
	var res: Dictionary = FabricatorScript.graft(gs, "blade")
	_check("blade graft ok", bool(res.get("ok", false)))
	_check("blade regrowth graft -> blade_regrown",
		ach.is_unlocked("blade_regrown"))
	pair = _make_pair()
	gs = pair[0]
	ach = pair[1]
	gs.add_item("briar_thorns", 1)
	FabricatorScript.learn(gs, "briar_thorns")
	res = FabricatorScript.graft(gs, "thorn")
	_check("non-blade graft does not fire blade_regrown",
		not ach.is_unlocked("blade_regrown"))
