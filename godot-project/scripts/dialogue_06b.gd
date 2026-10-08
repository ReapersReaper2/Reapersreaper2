extends RefCounted
## 06b Act 2 dialogue loader + trigger router for Reaper's Reaper.
##
## NOTE: intentionally no class_name (project convention). Load via preload.
##
## - Parses res://data/dialogue_06b.md with DialogueParser.
## - Maps doc scenes (Ch9-Ch12 + SQ1 + Astral Village + Bellmaw) to M3 rooms.
## - Routes [TRIGGER:] entries to real game systems (flags, forms, items,
##   quests). Unknown triggers log a warning instead of silently dropping.
## - Splits > **Choice:** scenes into pre/branches/post so the dialogue box
##   only plays the chosen branch.
##
## ctx Dictionaries passed to apply_trigger/apply_choice carry:
##   {"game_state": GameState-or-null, "room": room-or-null, "scene": scene-dict}

const DOC_PATH := "res://data/dialogue_06b.md"
const MemoriesScript := preload("res://scripts/memories.gd")

## room_id -> Array of {chapter, scene} matchers, in doc play order.
## Chapter strings match the doc's ## headings; scene strings match ### headings.
const ROOM_SCENES := {
	"f1": [
		{"chapter": "CHAPTER 9", "scene": "Scene 1: Ashen Peak approach"},
		{"chapter": "CHAPTER 9", "scene": "Scene 3: The missing apprentice"},
	],
	"f2": [
		{"chapter": "CHAPTER 9", "scene": "Scene 2: The forge door"},
		{"chapter": "CHAPTER 11", "scene": "Scene 2: No buyers"},
	],
	"f3": [
		{"chapter": "CHAPTER 9", "scene": "Scene 4: The mine"},
		{"chapter": "CHAPTER 9", "scene": "Scene 5: The realization"},
		{"chapter": "CHAPTER 9", "scene": "Scene 6: The longsword"},
	],
	"g1": [
		{"chapter": "CHAPTER 10", "scene": "Scene 1: The metal chamber"},
		{"chapter": "CHAPTER 10", "scene": "Scene 2: The arm with opinions"},
		{"chapter": "CHAPTER 10", "scene": "Scene 4: Luna"},
		{"chapter": "CHAPTER 10", "scene": "Scene 5: The kindness"},
		{"chapter": "SIDE QUEST 1", "scene": "Scene 1: Departure"},
	],
	"g2": [
		{"chapter": "CHAPTER 10", "scene": "Scene 3: Tendrils"},
	],
	"s1": [
		{"chapter": "SIDE QUEST 1", "scene": "Scene 2: The Subterranean Warrens"},
	],
	"s2": [
		{"chapter": "SIDE QUEST 1", "scene": "Scene 3: The Ground Sloths"},
		{"chapter": "SIDE QUEST 1", "scene": "Scene 4: Gravemaw"},
		{"chapter": "SIDE QUEST 1", "scene": "Scene 5: Campfire"},
		{"chapter": "SIDE QUEST 1", "scene": "Scene 6:"},
		{"chapter": "SIDE QUEST 1", "scene": "Scene 7: The walk back"},
	],
	"c2": [
		{"chapter": "CHAPTER 11", "scene": "Scene 1: The cache"},
	],
	"v1": [
		{"chapter": "ASTRAL VILLAGE", "scene": "Scene 1: Arrival"},
		{"chapter": "ASTRAL VILLAGE", "scene": "Scene 2: The price of rest"},
		{"chapter": "ASTRAL VILLAGE", "scene": "Scene 3: The Whisper-line"},
		{"chapter": "ASTRAL VILLAGE", "scene": "Scene 4: The elder's warning"},
	],
	"b1": [
		{"chapter": "BELLMAW", "scene": "Scene 1: The plateau"},
		{"chapter": "BELLMAW", "scene": "Scene 2: The experiment"},
		{"chapter": "BELLMAW", "scene": "Scene 3: Silence"},
	],
	"d1": [
		{"chapter": "CHAPTER 11", "scene": "Scene 3: The absorption"},
		{"chapter": "CHAPTER 11", "scene": "Scene 4: The seed"},
		{"chapter": "CHAPTER 12", "scene": "Scene 1: The ascent"},
	],
	"d2": [
		{"chapter": "CHAPTER 12", "scene": "Scene 2: Pressed hard"},
		{"chapter": "CHAPTER 12", "scene": "Scene 3: THE BLAST"},
		{"chapter": "CHAPTER 12", "scene": "Scene 4: The shore"},
		{"chapter": "CHAPTER 12", "scene": "Scene 5: Retrieved"},
	],
}


## Parse the doc. Returns [] on failure (with a push_error).
static func load_entries() -> Array:
	var parser = load("res://scripts/dialogue_parser.gd")
	if parser == null:
		push_error("dialogue_06b: DialogueParser failed to load")
		return []
	if not FileAccess.file_exists(DOC_PATH):
		push_error("dialogue_06b: doc not found: " + DOC_PATH)
		return []
	return parser.parse_file(DOC_PATH)


## Build an ordered scene index: [{chapter, heading, start, end, prelude}].
## Chapter context comes from the nearest preceding ## heading. `prelude`
## holds the entries between the ## heading and the scene (only non-empty
## for the first scene of a chapter) — chapter-level directions like the
## Bellmaw continuity lock live there.
static func build_scene_index(entries: Array) -> Array:
	var scenes: Array = []
	var chapter := ""
	var prelude_from := -1
	for i in entries.size():
		var e: Dictionary = entries[i]
		if e.get("type") != "scene_heading":
			continue
		var level := int(e.get("level", 0))
		var text := str(e.get("text", ""))
		if level == 2:
			chapter = text
			prelude_from = i + 1
		elif level == 3:
			var prelude: Array = []
			if prelude_from >= 0 and prelude_from < i:
				prelude = entries.slice(prelude_from, i)
			prelude_from = -1
			scenes.append({"chapter": chapter, "heading": text, "start": i,
				"end": entries.size(), "prelude": prelude})
			if scenes.size() > 1:
				scenes[scenes.size() - 2]["end"] = i
	return scenes


## Entries for one scene index record (heading excluded, body only).
static func entries_for_scene(entries: Array, rec: Dictionary) -> Array:
	var start := int(rec.get("start", 0)) + 1
	var end := int(rec.get("end", entries.size()))
	if start >= end:
		return []
	return entries.slice(start, end)


## All scenes for a room_id, in doc play order. Each item is
## {chapter, heading, entries, scene_index}.
static func scenes_for_room(entries: Array, room_id: String) -> Array:
	var result: Array = []
	var matchers: Array = ROOM_SCENES.get(room_id, [])
	if matchers.is_empty():
		return result
	var index := build_scene_index(entries)
	var used := {}
	for mi in matchers.size():
		var m: Dictionary = matchers[mi]
		var found := false
		for si in index.size():
			if used.has(si):
				continue
			var rec: Dictionary = index[si]
			if str(rec["chapter"]).contains(str(m["chapter"])) \
					and str(rec["heading"]).contains(str(m["scene"])):
				# Chapter prelude (directions between the ## heading and the
				# first ### scene) plays before the scene body.
				var body: Array = (rec.get("prelude", []) as Array).duplicate()
				body.append_array(entries_for_scene(entries, rec))
				result.append({
					"chapter": rec["chapter"],
					"heading": rec["heading"],
					"entries": body,
					"scene_index": si,
				})
				used[si] = true
				found = true
				break
		if not found:
			push_warning("dialogue_06b: no scene for room %s matcher %s" % [room_id, str(m)])
	# Propagate chapter-level continuity locks (e.g. the Bellmaw chapter's
	# "Luna is ABSENT", which lives in the chapter prelude) to every scene
	# in that chapter.
	var chapter_lock := {}
	for sc in result:
		var ch := str((sc as Dictionary)["chapter"])
		if not chapter_lock.has(ch):
			chapter_lock[ch] = false
		if not chapter_lock[ch]:
			for e in (sc as Dictionary).get("entries", []):
				if "Luna is ABSENT" in str((e as Dictionary).get("text", "")):
					chapter_lock[ch] = true
					break
	for sc in result:
		(sc as Dictionary)["hides_luna"] = chapter_lock[str((sc as Dictionary)["chapter"])]
	return result


## Split scene entries at the first > **Choice:** into
## {pre, choice, branches, post, order}.
## - pre: entries before the choice (heading already excluded).
## - choice: the choice entry dict ({} when none).
## - branches: key -> entries for *[If (KEY): ...]* conditional branches.
## - post: shared entries after the branches ("Either way"/"Whichever" and
##   everything following, or everything after the choice when there are no
##   conditionals).
## - order: branch keys in doc order.
static func split_at_choice(entries: Array) -> Dictionary:
	var pre: Array = []
	var choice := {}
	var ci := -1
	for i in entries.size():
		if (entries[i] as Dictionary).get("type") == "choice":
			choice = entries[i]
			ci = i
			break
		pre.append(entries[i])
	if ci < 0:
		return {"pre": entries.duplicate(), "choice": {}, "branches": {}, "post": [], "order": []}
	var branches := {}
	var order: Array = []
	var post: Array = []
	var cur := ""
	var cond_re := RegEx.new()
	cond_re.compile("^If\\s*\\(([A-Za-z0-9]+)\\)")
	for e in entries.slice(ci + 1):
		var ed: Dictionary = e
		if ed.get("type") == "conditional":
			var m := cond_re.search(str(ed.get("text", "")))
			if m:
				cur = m.get_string(1)
				if not branches.has(cur):
					branches[cur] = []
					order.append(cur)
				# Keep the conditional as a dim direction inside its branch.
				(branches[cur] as Array).append({"type": "direction", "text": str(ed.get("text", ""))})
				continue
		if ed.get("type") == "direction":
			var t := str(ed.get("text", ""))
			if t.begins_with("Either way") or t.begins_with("Whichever") or t.begins_with("Either "):
				cur = ""
				post.append(e)
				continue
		if cur != "":
			(branches[cur] as Array).append(e)
		else:
			post.append(e)
	return {"pre": pre, "choice": choice, "branches": branches, "post": post, "order": order}


## --- trigger routing ------------------------------------------------------

static func _set_flag(ctx: Dictionary, flag: String, value: bool = true) -> void:
	var gs = ctx.get("game_state")
	if gs != null and gs.has_method("set_flag"):
		gs.set_flag(flag, value)
	else:
		print("[D06B] flag (no game_state): ", flag, " = ", value)


static func _set_form(ctx: Dictionary, form: int) -> void:
	var gs = ctx.get("game_state")
	if gs != null and gs.has_method("set_form"):
		gs.set_form(form)
	_set_flag(ctx, "form%d_unlocked" % form)


## Route one [TRIGGER:] text to game systems. ctx: see file header.
static func apply_trigger(trigger_text: String, ctx: Dictionary) -> void:
	var t := trigger_text
	# Ch9 — Forgehold.
	if t.contains("Ashen Peak region unlock"):
		_set_flag(ctx, "region_ashen_peak")
		# Ash wraiths live in the f1 encounter table (data/encounters.json).
	elif t.contains("Quest \"The Cold Forge\" begins"):
		_set_flag(ctx, "q_cold_forge_started")
	elif t.contains("Dungeon \"The Abandoned Mine\" unlocks"):
		_set_flag(ctx, "dungeon_abandoned_mine")
	elif t.contains("Ancient One foreshadow flag 1/3"):
		_set_flag(ctx, "ancient_foreshadow_1")
	elif t.contains("Quest \"The Cold Forge\" complete"):
		_set_flag(ctx, "q_cold_forge_done")
		_set_flag(ctx, "forge_door_open")
	elif t.contains("Form 4 unlock"):
		_set_form(ctx, 4)  # BLACKSMITH ARMOR; armor_born fires in set_form.
	# Ch10 — What It Decides.
	elif t.contains("Form 5 unlock"):
		_set_form(ctx, 5)  # PLANT ARMOR I; green_burial fires in set_form.
	elif t.contains("Form 5 active"):
		_set_flag(ctx, "bloom_meter_silent")
	elif t.contains("Grafting system online"):
		_set_flag(ctx, "grafting_unlocked")
	elif t.contains("Form 6 unlock"):
		_set_form(ctx, 6)  # PLANT ARMOR II; tendril traversal enabled.
	elif t.contains("Bloom meter tutorial complete"):
		_set_flag(ctx, "bloom_ui_unlocked")
	# SQ1 — Tucker and the Sloths.
	elif t.contains("Quest \"Tucker and the Sloths\" begins"):
		_set_flag(ctx, "q_sloths_started")
	elif t.contains("Ancient One foreshadow flag 2/3"):
		_set_flag(ctx, "ancient_foreshadow_2")
	elif t.contains("sloth_oath"):
		_set_flag(ctx, "sloth_oath")
		_set_flag(ctx, "q_sloths_done")
	# Ch11 — The Broken Mini Cannon.
	elif t.contains("Key item acquired") and t.contains("Ancient Revolver"):
		var gs = ctx.get("game_state")
		if gs != null and gs.has_method("add_item"):
			gs.add_item("ancient_revolver", 1)
		_set_flag(ctx, "revolver_acquired")
	elif t.contains("revolver_sold"):
		# Wiring note: fences refuse the revolver; if "sold" it returns.
		_set_flag(ctx, "revolver_unsellable")
	elif t.contains("Form 7 unlock"):
		_set_form(ctx, 7)  # CANNON ASSIMILATION.
		_set_flag(ctx, "arm_cannon")
	# Astral Village.
	elif t.contains("Waypoint \"The Astral Village\" discovered"):
		_set_flag(ctx, "waypoint_astral_village")
	elif t.contains("Remove selected memory from flashback pool"):
		_set_flag(ctx, "memory_traded")
	elif t.contains("Astral projection unlock"):
		_set_flag(ctx, "projection_unlocked")
	# Bellmaw.
	elif t.contains("Puzzle-boss"):
		_set_flag(ctx, "bellmaw_puzzle")
	elif t.contains("Cloudbloom Plateau cleared"):
		_set_flag(ctx, "bellmaw_defeated")
	# Ch12 — Mount Dragoni.
	elif t.contains("Multi-wave combat begins"):
		_set_flag(ctx, "dragoni_ambush")
	elif t.contains("The blast as a limited super-move"):
		_set_flag(ctx, "blast_supermove")
	elif t.contains("Chapter complete."):
		_set_flag(ctx, "ch12_complete")
	else:
		push_warning("dialogue_06b: unrouted trigger: " + t.left(80))


## --- choice consequences --------------------------------------------------

## Apply a > **Choice:** pick. ctx carries "choice_id" ("revolver" or "memory")
## set by the room script from the current scene.
static func apply_choice(option: Dictionary, ctx: Dictionary) -> void:
	var key := str(option.get("key", ""))
	var text := str(option.get("text", ""))
	var choice_id := str(ctx.get("choice_id", ""))
	if choice_id == "":
		# Fall back to text matching when the room didn't tag the choice.
		if text.contains("scrap") or text.contains("Take it back"):
			choice_id = "revolver"
		elif text.contains("horsemen") or text.contains("church bells") \
				or text.contains("silver helmet") or text.contains("invaders"):
			choice_id = "memory"
	if choice_id == "revolver":
		_set_flag(ctx, "revolver_choice_" + key)
		_set_flag(ctx, "revolver_kept")
		# Either branch: the revolver stays with Mollosar (doc canon).
	elif choice_id == "memory":
		# Inn trade: map the choice letter (A-D) to the real memory key and
		# burn it permanently via the memory economy. Fail-safe: an already-
		# spent memory cannot be traded twice.
		var mem_key := MemoriesScript.trade_key_for_letter(key)
		var gs_m = ctx.get("game_state")
		if mem_key != "" and MemoriesScript.trade(gs_m, mem_key):
			pass  # traded: flashback_gone_<key> + memory_traded are set.
		else:
			push_warning("dialogue_06b: memory trade failed for key '" + key + "'")
	else:
		push_warning("dialogue_06b: unrouted choice: " + text.left(60))


## Identify which choice a scene's choice entry is ("" when none).
static func choice_id_for_scene(scene: Dictionary) -> String:
	var split := split_at_choice(scene.get("entries", []))
	var choice: Dictionary = split.get("choice", {})
	if choice.is_empty():
		return ""
	var opts: Array = choice.get("options", [])
	for o in opts:
		var ot := str((o as Dictionary).get("text", ""))
		if ot.contains("scrap") or ot.contains("Take it back"):
			return "revolver"
		if ot.contains("horsemen") or ot.contains("church bells"):
			return "memory"
	return "generic"


## True when any entry in the scene carries the Luna-absence continuity lock
## (or the scene's chapter prelude does — see scenes_for_room).
static func scene_hides_luna(scene: Dictionary) -> bool:
	if bool(scene.get("hides_luna", false)):
		return true
	for e in scene.get("entries", []):
		if "Luna is ABSENT" in str((e as Dictionary).get("text", "")):
			return true
	return false
