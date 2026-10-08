extends SceneTree
## Headless Steam-groundwork test: achievements, stats, save persistence.
## Run: ./Godot_v4.3-stable_linux.x86_64 --headless --path <project> -s res://scripts/steam_test.gd
## Uses throwaway slots 90-99 so real saves are never touched.
## (Autoloads are not loaded under -s, so scripts are instantiated via load()
## and wired by hand, same pattern as save_test.gd.)

var _failures: Array[String] = []


func _check(name: String, cond: bool) -> void:
	if cond:
		print("  PASS: ", name)
	else:
		_failures.append(name)
		print("  FAIL: ", name)


func _init() -> void:
	print("=== STEAM GROUNDWORK TEST ===")
	var save_system_script = load("res://scripts/save_system.gd")
	var game_state_script = load("res://scripts/game_state.gd")
	var achievements_script = load("res://scripts/achievements.gd")
	var stats_script = load("res://scripts/stats.gd")

	var ss = save_system_script.new()
	ss.name = "SaveSystem"
	root.add_child(ss)
	var gs = game_state_script.new()
	gs.name = "GameState"
	gs.save_system = ss
	root.add_child(gs)
	var ach = achievements_script.new()
	ach.name = "Achievements"
	ach.game_state = gs
	root.add_child(ach)
	gs.achievements = ach
	var st = stats_script.new()
	st.name = "Stats"
	st.game_state = gs
	st.achievements = ach
	root.add_child(st)
	# NOTE: under -s, _ready() does not auto-fire for nodes added in _init().
	gs._ready()
	ach._ready()
	st._ready()

	# 1. Achievement table shape.
	_check("43 achievements defined (20 launch + 23 steam)", ach.total_count() == 43)
	_check("steam ids present", (achievements_script.ACHIEVEMENTS as Dictionary).has("drowned_dice"))
	_check("steam hidden flags", bool((achievements_script.ACHIEVEMENTS["gardener"] as Dictionary).get("hidden", false)) == true)
	_check("hidden flag present", bool((achievements_script.ACHIEVEMENTS["invader_slayer_100"] as Dictionary).get("hidden", false)) == true)
	_check("flag map has collapse", str((achievements_script.FLAG_ACHIEVEMENTS as Dictionary).get("p2_collapse_seen", "")) == "collapse_seen")

	# 2. Unlock is idempotent.
	_check("unlock returns true", ach.unlock("first_reap") == true)
	_check("is_unlocked", ach.is_unlocked("first_reap") == true)
	_check("count is 1", ach.unlock_count() == 1)
	ach.unlock("first_reap")
	_check("second unlock still count 1", ach.unlock_count() == 1)

	# 3. Unknown id warns cleanly, changes nothing.
	_check("unknown unlock returns false", ach.unlock("nope_not_real") == false)
	_check("unknown unlock keeps count", ach.unlock_count() == 1)

	# 4. Kill thresholds drive achievements.
	st.reset_all()
	ach.reset_all()
	for i in range(25):
		st.record_kill()
	_check("25 kills -> slayer_25", ach.is_unlocked("invader_slayer_25"))
	_check("25 kills -> first_reap", ach.is_unlocked("first_reap"))
	_check("25 kills not yet slayer_100", not ach.is_unlocked("invader_slayer_100"))
	for i in range(75):
		st.record_kill()
	_check("100 kills -> slayer_100", ach.is_unlocked("invader_slayer_100"))

	# 5. Guide thresholds.
	for i in range(10):
		st.record_guide()
	_check("1+ guides -> bounty_done", ach.is_unlocked("bounty_done"))
	_check("10 guides -> wisp_guide_10", ach.is_unlocked("wisp_guide_10"))

	# 6. Explorer: all three M1 rooms.
	st.record_room("p1")
	_check("explorer not yet after 1 room", not ach.is_unlocked("explorer"))
	st.record_room("p3")
	st.record_room("c1")
	_check("explorer after p1+p3+c1", ach.is_unlocked("explorer"))
	st.record_room("p1")
	_check("room re-entry harmless", ach.is_unlocked("explorer"))

	# 7. Waves cleared with damage taken: bridge yes, deathless no.
	st.reset_all()
	ach.reset_all()
	st.record_damage(2)
	_check("damage tracked", int((st.get_stats() as Dictionary).get("damage_taken_p1", 0)) == 2)
	st.on_waves_cleared()
	_check("waves cleared -> bridge_cleared", ach.is_unlocked("bridge_cleared"))
	_check("damage taken -> no deathless", not ach.is_unlocked("deathless_p1"))

	# 8. Waves cleared clean: deathless unlocks.
	st.reset_all()
	ach.reset_all()
	st.on_waves_cleared()
	_check("clean clear -> deathless_p1", ach.is_unlocked("deathless_p1"))

	# 9. Full combo.
	st.record_combo_hits(1)
	_check("combo 1 hit no unlock", not ach.is_unlocked("full_combo"))
	st.record_combo_hits(2)
	_check("combo 2 hits -> full_combo", ach.is_unlocked("full_combo"))

	# 10. Flag-based unlock (cutscene trigger path).
	ach.unlock_for_flag("p2_collapse_seen")
	_check("flag unlock -> collapse_seen", ach.is_unlocked("collapse_seen"))
	ach.unlock_for_flag("some_random_flag")
	_check("unmapped flag harmless", ach.unlock_count() == 4)  # deathless, full_combo, collapse + keeper? no — count below

	# 11. Shrine save unlocks keeper.
	ach.reset_all()
	_check("shrine save ok", gs.save_shrine(95) == true)
	_check("shrine save -> keeper", ach.is_unlocked("keeper"))

	# 12. Save/load round-trip preserves achievements + stats.
	st.record_kill()
	st.record_kill()
	st.record_room("p1")
	ach.unlock("bridge_cleared")
	_check("pre-save count sane", ach.unlock_count() >= 1)
	_check("save ok", gs.save_to_slot(96) == true)
	# Mutate live state, then load back.
	ach.reset_all()
	st.reset_all()
	_check("after reset count 0", ach.unlock_count() == 0)
	_check("load ok", gs.load_from_slot(96) == true)
	# load_from_slot emits state_loaded -> stats re-pulls.
	_check("achievements survive load", ach.unlock_count() >= 1)
	_check("stats survive load", int((st.get_stats() as Dictionary).get("reap_kills", -1)) == 2)
	_check("rooms survive load", ((st.get_stats() as Dictionary).get("rooms_entered", []) as Array).has("p1"))
	ss.delete_save(95)
	ss.delete_save(96)

	# 13. Steam hook point exists and doesn't error.
	ach._steam_unlock("bridge_cleared")
	_check("steam hook callable", true)
	ach.steam_sync()
	_check("steam_sync callable", true)

	# 14. Save dir helper.
	_check("get_save_dir", ss.get_save_dir() == "user://saves")
	_check("default save has stats", (save_system_script.default_save() as Dictionary).has("stats"))
	_check("default save ledger has achievements", ((save_system_script.default_save() as Dictionary)["ledger"] as Dictionary).has("achievements"))

	print("=== STEAM TEST: %d failures ===" % _failures.size())
	for f in _failures:
		print("  FAILED: ", f)
	if _failures.is_empty():
		quit(0)
	else:
		quit(1)
