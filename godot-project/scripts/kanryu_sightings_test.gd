extends SceneTree
## Headless Kanryu sighting beats test (V1-V4 wiring).
## Run: Godot --headless --path <project> -s res://scripts/kanryu_sightings_test.gd
##
## Pins: registry caps the four beat rooms (g2, s2, f3, gd6 — one each, no
## others); the silhouette is non-interactable (no Area2D, no Label, no
## prompt/inspect/dialogue/journal keys in the config); the beat never
## touches journal APIs; approach-cutoff fades the figure to invisible and
## spends the one-shot flag; V1 plays the canon Luna line verbatim (g2 only,
## once) while V2-V4 stay silent; items.json twins_lent name == "Lent Twin"
## (note unchanged) and dragon_gold material entry pinned; LESSER_FORM_THRESHOLD
## == 48 with the tune-tagged marker.

const Sighting := preload("res://scripts/kanryu_sighting.gd")
const WrathAlly := preload("res://scripts/wrath_ally.gd")

var _failures := 0
var _passes := 0


class FakeRoom extends Node2D:
	var room_id := ""
	var flags := {}
	var dialogue_box = null  # capturing fake in V1-line tests
	func _flag(f: String) -> bool:
		return bool(flags.get(f, false))
	func _set_flag(f: String, v: bool = true) -> void:
		flags[f] = v


## Captures start_dialogue calls so the V1 canon line can be pinned
## without the real DialogueBox.
class FakeDialogueBox extends Node:
	var played: Array = []
	func start_dialogue(entries: Array, start_index: int = 0) -> void:
		played.append_array(entries)


func _check(name: String, cond: bool) -> void:
	if cond:
		_passes += 1
	else:
		_failures += 1
		print("  FAILED: ", name)


func _make_fake_room(room_id: String) -> FakeRoom:
	var r := FakeRoom.new()
	r.room_id = room_id
	root.add_child(r)  # in-tree so _ready() runs on attach
	return r


func _make_player(pos: Vector2) -> Node2D:
	_clear_players()  # queue_free is deferred; stale group members break first-in-group lookups
	var p := Node2D.new()
	p.name = "FakePlayer"
	p.position = pos
	p.add_to_group("player")
	root.add_child(p)
	return p


func _clear_players() -> void:
	for c in root.get_children():
		if c.is_in_group("player"):
			root.remove_child(c)
			c.free()


func _init() -> void:
	print("[kanryu_sightings_test] starting")
	_run.call_deferred()


func _run() -> void:
	_test_registry_cap()
	_test_attach_and_visual()
	_test_non_interactable()
	_test_no_journal_no_story_apis()
	_test_approach_cutoff()
	_test_v1_luna_line()
	_test_one_shot()
	_test_items_json_pin()
	_test_threshold_tune_tag()
	var total := _passes + _failures
	print("[TEST] kanryu_sightings: %d passed, %d failed (of %d)" % [_passes, _failures, total])
	if _failures > 0:
		quit(1)
	else:
		quit(0)


func _test_registry_cap() -> void:
	var rooms: Array = Sighting.beat_rooms()
	rooms.sort()
	_check("registry has exactly 4 beats", rooms.size() == 4)
	_check("registry rooms are f3,g2,gd6,s2", rooms == ["f3", "g2", "gd6", "s2"])
	for rid in ["g2", "s2", "f3", "gd6"]:
		_check("is_beat_room(%s)" % rid, Sighting.is_beat_room(rid))
	for rid in ["g1", "s1", "f1", "f2", "h2", "c2", "gd5", "p1", ""]:
		_check("not a beat room: %s" % rid, not Sighting.is_beat_room(rid))


func _test_attach_and_visual() -> void:
	_check("attach returns null for non-beat room", Sighting.attach_to(_make_fake_room("g1")) == null)
	var room := _make_fake_room("g2")
	var node := Sighting.attach_to(room)
	_check("attach spawns node for g2", node != null)
	_check("sighting positioned at beat pos",
		node.position == (Sighting.KANRYU_BEATS["g2"] as Dictionary).get("pos"))
	var fig := node.get_node_or_null("DistantFigure")
	_check("silhouette node exists", fig != null)
	_check("silhouette visible on spawn", fig.visible)
	_check("silhouette starts fully opaque", node.figure_alpha() == 1.0)
	# Name check: no player-facing name string on the figure.
	_check("no name text on figure", fig.get("text") == null)
	node.queue_free()


func _test_non_interactable() -> void:
	for rid in ["g2", "s2", "f3", "gd6"]:
		var room := _make_fake_room(rid)
		var node := Sighting.attach_to(room)
		var areas := []
		var labels := []
		_collect(node, areas, labels)
		_check("%s: no Area2D under sighting" % rid, areas.is_empty())
		_check("%s: no Label under sighting" % rid, labels.is_empty())
		var cfg: Dictionary = Sighting.KANRYU_BEATS[rid]
		for banned in ["name", "dialogue", "journal", "inspect", "prompt", "lines"]:
			_check("%s: config has no '%s' key" % [rid, banned], not cfg.has(banned))
		node.queue_free()


func _collect(n: Node, areas: Array, labels: Array) -> void:
	if n is Area2D:
		areas.append(n)
	if n is Label:
		labels.append(n)
	for c in n.get_children():
		_collect(c, areas, labels)


func _test_no_journal_no_story_apis() -> void:
	var path := "res://scripts/kanryu_sighting.gd"
	var f := FileAccess.open(path, FileAccess.READ)
	var src := f.get_as_text()
	f.close()
	# Strip comments: the rule-doc comments legitimately mention story APIs.
	var code := PackedStringArray()
	for line in src.split("\n"):
		var hash_pos := line.find("#")
		if hash_pos >= 0:
			line = line.substr(0, hash_pos)
		code.append(line)
	var low := "\n".join(code).to_lower()
	# "dialogue"/"start_dialogue" are NOT banned outright: the V1 canon Luna
	# line plays verbatim through the room's dialogue box (see pins below).
	# Everything else on the story side stays out.
	for banned in ["journal", "prompt_text", "inspect", "kanryu_announce"]:
		_check("source has no story API: " + banned, not banned in low)
	# Pin the single dialogue call site: the only start_dialogue invocation
	# in code must be the V1 line, gated inside _play_v1_line.
	var calls := 0
	for line in code:
		if "has_method" in line:
			continue  # guard line, not a call
		if "start_dialogue" in line and "func " not in line:
			calls += 1
			_check("only call site is start_dialogue(V1_LUNA_LINE)",
				"start_dialogue(V1_LUNA_LINE)" in line)
	_check("exactly one start_dialogue call site", calls == 1)
	_check("V1 line is g2-gated", '_room_id != "g2"' in low)
	# No name string is surfaced: the only "Kanryu" mentions are internal
	# flag/script references, never a shown name.
	_check("no player-facing name literal", not ('"Kanryu"' in src) and not ("'Kanryu'" in src))


func _test_approach_cutoff() -> void:
	var room := _make_fake_room("g2")
	var player := _make_player(Vector2(0, 100))  # at spawn, far from the figure
	var node := Sighting.attach_to(room)
	# Player at spawn: no crossing yet.
	node._process(0.0)
	_check("spawn position does not cross", not node.is_fading())
	# Walk past the mid-distance approach line (g2 line at y=-230, dir -1).
	player.position = Vector2(330, -300)
	node._process(0.0)
	_check("crossing the line starts the fade", node.is_fading())
	node._process(0.6)
	var mid: float = node.figure_alpha()
	_check("fade is partial midway", mid < 1.0 and mid > 0.0)
	node._process(0.7)
	_check("fade completes (alpha 0)", node.figure_alpha() == 0.0)
	_check("one-shot flag set", room._flag("kanryu_sight_done_g2"))
	_check("sighting removed after fade", node.is_queued_for_deletion())
	player.queue_free()
	_clear_players()


func _test_v1_luna_line() -> void:
	# Canon text pinned verbatim (story-bot locked 2026-10-05).
	var line: Array = Sighting.V1_LUNA_LINE
	_check("V1 line has exactly 2 entries", line.size() == 2)
	_check("V1 entry 1 is LUNA verbatim",
		str(line[0].get("type", "")) == "dialogue"
		and str(line[0].get("character", "")) == "LUNA"
		and str(line[0].get("text", "")) == "...Did you see that?")
	_check("V1 entry 2 is MOLLOSAR verbatim",
		str(line[1].get("type", "")) == "dialogue"
		and str(line[1].get("character", "")) == "MOLLOSAR"
		and str(line[1].get("text", "")) == "See what?")
	# Fires once for g2, at fade start ("gone when you blink").
	var room := _make_fake_room("g2")
	var box := FakeDialogueBox.new()
	root.add_child(box)
	room.dialogue_box = box
	var player := _make_player(Vector2(0, 100))
	var node := Sighting.attach_to(room)
	_check("g2: no line before the approach line", box.played.is_empty())
	player.position = Vector2(330, -300)  # past the g2 approach line
	node._process(0.0)
	_check("g2: line plays at fade start", box.played.size() == 2)
	_check("g2: line is the canon entries",
		str(box.played[0].get("text", "")) == "...Did you see that?"
		and str(box.played[1].get("text", "")) == "See what?")
	node._process(1.3)  # finish the fade; beat spent
	_check("g2: line does not replay", box.played.size() == 2)
	player.queue_free()
	# V2-V4 stay SILENT: no dialogue even with a box present.
	for rid in ["s2", "f3", "gd6"]:
		var r := _make_fake_room(rid)
		var b := FakeDialogueBox.new()
		root.add_child(b)
		r.dialogue_box = b
		var p := _make_player(Vector2(0, 100))
		var n := Sighting.attach_to(r)
		if rid == "gd6":
			p.position = Vector2(600, 100)
		else:
			p.position = Vector2(0, -400)  # past the y-axis approach lines
		n._process(0.0)
		_check("%s: stays silent (no dialogue)" % rid, b.played.is_empty())
		p.queue_free()
		n.queue_free()
	_clear_players()


func _test_one_shot() -> void:
	var room := _make_fake_room("s2")
	room._set_flag("kanryu_sight_done_s2")
	_check("spent beat does not re-attach", Sighting.attach_to(room) == null)
	# gd6 uses the x-axis approach line.
	var room2 := _make_fake_room("gd6")
	var player := _make_player(Vector2(0, 100))
	var node := Sighting.attach_to(room2)
	node._process(0.0)
	_check("gd6: spawn does not cross", not node.is_fading())
	player.position = Vector2(600, 100)  # past line x=480 toward the figure
	node._process(0.0)
	_check("gd6: x-axis crossing starts the fade", node.is_fading())
	player.queue_free()


func _test_items_json_pin() -> void:
	var f := FileAccess.open("res://data/items.json", FileAccess.READ)
	var data: Dictionary = JSON.parse_string(f.get_as_text())
	f.close()
	var rec: Dictionary = (data.get("items", {}) as Dictionary).get("twins_lent", {})
	_check("twins_lent name is Lent Twin", str(rec.get("name", "")) == "Lent Twin")
	_check("twins_lent note unchanged", str(rec.get("note", "")) == "don't scratch the gold")
	_check("twins_lent internal id still present", (data.get("items", {}) as Dictionary).has("twins_lent"))
	# dragon_gold material entry (story-bot confirmed 2026-10-05): discoverable
	# late-game material; price unset (balance pass).
	var dg: Dictionary = (data.get("items", {}) as Dictionary).get("dragon_gold", {})
	_check("dragon_gold entry present", not dg.is_empty())
	_check("dragon_gold name is Dragon Gold", str(dg.get("name", "")) == "Dragon Gold")
	_check("dragon_gold kind is material", str(dg.get("kind", "")) == "material")
	_check("dragon_gold desc names the Twins", "Twins" in str(dg.get("desc", "")))
	_check("dragon_gold desc covers soul-flame", "soul-flame" in str(dg.get("desc", "")))
	_check("dragon_gold desc gates late-game source", "Forgehold" in str(dg.get("desc", "")))


func _test_threshold_tune_tag() -> void:
	_check("LESSER_FORM_THRESHOLD == 48", WrathAlly.LESSER_FORM_THRESHOLD == 48)
	var f := FileAccess.open("res://scripts/wrath_ally.gd", FileAccess.READ)
	var src := f.get_as_text()
	f.close()
	_check("threshold carries [TUNING] marker", "[TUNING]" in src)
	_check("marker disclaims canon lock", "NOT a canon lock" in src)
