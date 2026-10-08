extends SceneTree
## Headless 06b Act 2 dialogue wiring test: doc parses cleanly, every scene
## maps to an M3 room, every [TRIGGER:] routes to a real system, both
## > **Choice:** branches split correctly, and data hooks exist.
##
## Run: ./Godot_v4.3-stable_linux.x86_64 --headless --path <project> -s res://scripts/dialogue_06b_test.gd

const D06B := preload("res://scripts/dialogue_06b.gd")

var _failed := 0
var _passed := 0


class MockGS extends RefCounted:
	var flags := {}
	var items := {}
	var form := 1
	func set_flag(f: String, v: bool = true) -> void:
		flags[f] = v
	func get_flag(f: String, d: bool = false) -> bool:
		return bool(flags.get(f, d))
	func add_item(item_id: String, n: int = 1) -> void:
		items[item_id] = int(items.get(item_id, 0)) + n
	func set_form(f: int) -> void:
		form = f


func _check(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		push_error("[TEST] FAIL: " + label)


func _initialize() -> void:
	print("[TEST] dialogue_06b test starting")


func _find_scene(scenes: Array, chapter_sub: String, scene_sub: String) -> Dictionary:
	for sc in scenes:
		var d: Dictionary = sc
		if str(d["chapter"]).contains(chapter_sub) and str(d["heading"]).contains(scene_sub):
			return d
	return {}


func _process(_delta: float) -> bool:
	_run()
	print("[TEST] dialogue_06b: %d passed, %d failed" % [_passed, _failed])
	quit()
	return true


func _run() -> void:
	# --- 1. doc parses cleanly ---
	var entries: Array = D06B.load_entries()
	_check(not entries.is_empty(), "doc parses to non-empty entries")
	var counts := {}
	for e in entries:
		var t: String = (e as Dictionary).get("type", "?")
		counts[t] = int(counts.get(t, 0)) + 1
	_check(int(counts.get("trigger", 0)) >= 20, "triggers parsed (>=20, got %d)" % int(counts.get("trigger", 0)))
	_check(int(counts.get("choice", 0)) == 2, "exactly 2 choices parsed")
	_check(int(counts.get("conditional", 0)) == 2, "2 conditionals parsed (revolver branches)")

	# --- 2. scene index: 35 scenes across 7 chapters + the story-bot-owned
	# widowblade_planting_beat beat section (appended 2026-10-05; not a
	# room-mapped scene, so the "all scenes mapped" total below stays 34) ---
	var index: Array = D06B.build_scene_index(entries)
	_check(index.size() == 35, "35 scenes indexed (got %d)" % index.size())

	# --- 3. every room matcher resolves; all 12 rooms covered; no scene reused ---
	var rooms := ["f1", "f2", "f3", "g1", "g2", "s1", "s2", "c2", "v1", "b1", "d1", "d2"]
	var total := 0
	var seen_idx := {}
	for r in rooms:
		var scenes: Array = D06B.scenes_for_room(entries, r)
		var expected: int = (D06B.ROOM_SCENES[r] as Array).size()
		_check(scenes.size() == expected, "room %s: %d scenes (expected %d)" % [r, scenes.size(), expected])
		for sc in scenes:
			var si := int((sc as Dictionary)["scene_index"])
			_check(not seen_idx.has(si), "scene %d used once (room %s)" % [si, r])
			seen_idx[si] = r
			_check(not ((sc as Dictionary).get("entries", []) as Array).is_empty(), "room %s scene %d has entries" % [r, si])
		total += scenes.size()
	_check(total == 34, "all 34 scenes mapped across rooms (got %d)" % total)
	_check(D06B.scenes_for_room(entries, "zzz").is_empty(), "unknown room maps to no scenes")

	# --- 4. every trigger routes to a real system ---
	var routed := 0
	var trigger_texts: Array = []
	for r in rooms:
		for sc in D06B.scenes_for_room(entries, r):
			for e in (sc as Dictionary).get("entries", []):
				if (e as Dictionary).get("type") == "trigger":
					trigger_texts.append(str((e as Dictionary).get("text", "")))
	for tt in trigger_texts:
		var gs := MockGS.new()
		D06B.apply_trigger(tt, {"game_state": gs, "room": null, "scene": {}})
		if not gs.flags.is_empty() or not gs.items.is_empty() or gs.form != 1:
			routed += 1
	_check(routed == trigger_texts.size(), "all %d triggers routed (got %d)" % [trigger_texts.size(), routed])

	# Spot-check key trigger effects.
	var gs := MockGS.new()
	D06B.apply_trigger("Ashen Peak region unlock. Random encounters: ash wraiths.", {"game_state": gs})
	_check(gs.get_flag("region_ashen_peak"), "trigger: region_ashen_peak")
	D06B.apply_trigger("Form 4 unlock — BLACKSMITH ARMOR.", {"game_state": gs})
	_check(gs.form == 4 and gs.get_flag("form4_unlocked"), "trigger: form 4")
	D06B.apply_trigger("Form 5 unlock — PLANT ARMOR I.", {"game_state": gs})
	_check(gs.form == 5, "trigger: form 5")
	D06B.apply_trigger("Form 6 unlock — PLANT ARMOR II.", {"game_state": gs})
	_check(gs.form == 6, "trigger: form 6")
	D06B.apply_trigger("Form 7 unlock — CANNON ASSIMILATION.", {"game_state": gs})
	_check(gs.form == 7 and gs.get_flag("arm_cannon"), "trigger: form 7 + arm cannon")
	D06B.apply_trigger("Key item acquired — \"Ancient Revolver\" (broken).", {"game_state": gs})
	_check(int(gs.items.get("ancient_revolver", 0)) == 1, "trigger: ancient revolver item")
	D06B.apply_trigger("Quest complete. [WIRING: Set flag \"sloth_oath\" — changes the final act.]", {"game_state": gs})
	_check(gs.get_flag("sloth_oath") and gs.get_flag("q_sloths_done"), "trigger: sloth_oath")
	D06B.apply_trigger("Cloudbloom Plateau cleared.", {"game_state": gs})
	_check(gs.get_flag("bellmaw_defeated"), "trigger: bellmaw_defeated")
	D06B.apply_trigger("[WIRING: Astral projection unlock — limited traversal/dungeon mechanic.]", {"game_state": gs})
	_check(gs.get_flag("projection_unlocked"), "trigger: projection_unlocked")

	# --- 5. choice splits ---
	var f2_scenes: Array = D06B.scenes_for_room(entries, "f2")
	var no_buyers := _find_scene(f2_scenes, "CHAPTER 11", "No buyers")
	_check(not no_buyers.is_empty(), "f2 has Ch11 'No buyers' scene")
	var split: Dictionary = D06B.split_at_choice(no_buyers.get("entries", []))
	_check((split["choice"] as Dictionary).get("options", []).size() == 2, "revolver choice: 2 options")
	_check((split["branches"] as Dictionary).has("A") and (split["branches"] as Dictionary).has("B"), "revolver: branches A and B")
	var post_text := ""
	for e in split["post"] as Array:
		post_text += str((e as Dictionary).get("text", "")) + " "
	_check("Either way" in post_text, "revolver: 'Either way' shared post")
	_check(D06B.choice_id_for_scene(no_buyers) == "revolver", "choice id: revolver")

	var v1_scenes: Array = D06B.scenes_for_room(entries, "v1")
	var price := _find_scene(v1_scenes, "ASTRAL VILLAGE", "price of rest")
	_check(not price.is_empty(), "v1 has 'price of rest' scene")
	var msplit: Dictionary = D06B.split_at_choice(price.get("entries", []))
	_check((msplit["choice"] as Dictionary).get("options", []).size() == 4, "memory choice: 4 options")
	_check((msplit["branches"] as Dictionary).is_empty(), "memory choice: no conditional branches")
	_check(not (msplit["post"] as Array).is_empty(), "memory choice: shared post")
	_check(D06B.choice_id_for_scene(price) == "memory", "choice id: memory")

	# Choice consequences.
	var gs2 := MockGS.new()
	D06B.apply_choice({"key": "A", "text": "Leave it for scrap.", "tags": []},
		{"game_state": gs2, "choice_id": "revolver"})
	_check(gs2.get_flag("revolver_choice_A") and gs2.get_flag("revolver_kept"), "choice: revolver A keeps revolver")
	var gs3 := MockGS.new()
	D06B.apply_choice({"key": "C", "text": "The silver helmet.", "tags": []},
		{"game_state": gs3, "choice_id": "memory"})
	_check(gs3.get_flag("memory_traded") and gs3.get_flag("flashback_gone_silver_helmet"),
		"choice: memory C removes the silver helmet flashback")

	# --- 6. Luna continuity lock ---
	var b1_scenes: Array = D06B.scenes_for_room(entries, "b1")
	var hides := 0
	for sc in b1_scenes:
		if D06B.scene_hides_luna(sc):
			hides += 1
	_check(hides == 3, "all 3 Bellmaw scenes hide Luna (got %d)" % hides)
	var g1_scenes: Array = D06B.scenes_for_room(entries, "g1")
	var g1_hides := 0
	for sc in g1_scenes:
		if D06B.scene_hides_luna(sc):
			g1_hides += 1
	_check(g1_hides == 0, "no g1 scene hides Luna")

	# --- 7. data hooks ---
	var quests: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/quests.json"))
	var qids := []
	for qd in quests["quests"]:
		qids.append(str((qd as Dictionary)["id"]))
	_check("q_cold_forge" in qids, "quest q_cold_forge in quests.json")
	_check("q_sloths" in qids, "quest q_sloths in quests.json")
	var items: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/items.json"))
	_check((items["items"] as Dictionary).has("ancient_revolver"), "ancient_revolver in items.json")
	var creatures: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/creatures.json"))
	var cdict: Dictionary = creatures.get("creatures", creatures)
	_check(cdict.has("ash_wraith"), "ash_wraith in creatures.json")
	var encounters: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/encounters.json"))
	var f1_has := false
	for row in encounters.get("f1", []):
		if str((row as Dictionary).get("creature_id", "")) == "ash_wraith":
			f1_has = true
	_check(f1_has, "ash_wraith in f1 encounter table")

	# --- 8. room scenes wired to room_act2.gd ---
	for r in rooms:
		var tscn := FileAccess.get_file_as_string("res://scenes/room_%s.tscn" % r)
		_check(tscn.contains("res://scripts/room_act2.gd"), "room_%s.tscn uses room_act2.gd" % r)
