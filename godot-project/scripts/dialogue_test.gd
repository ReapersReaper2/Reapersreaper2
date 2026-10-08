extends SceneTree
## Headless smoke test: parse 06a, print scenes + first scene structure,
## and sanity-check the dialogue_box.tscn loads.
## Run: ./Godot_v4.3-stable_linux.x86_64 --headless --path <project> -s res://scripts/dialogue_test.gd

const DOC_PATH := "/home/hatch/workspace/user/files/reapers-reaper/story-package/06a-dialogue-act1.md"


func _init() -> void:
	var parser = load("res://scripts/dialogue_parser.gd")
	var entries: Array = parser.parse_file(DOC_PATH)
	print("=== PARSE RESULT ===")
	print("total entries: ", entries.size())

	var counts := {}
	for e in entries:
		var t: String = e.get("type", "?")
		counts[t] = int(counts.get(t, 0)) + 1
	print("by type: ", counts)

	var scenes: Array = parser.get_scenes(entries)
	print("scenes found: ", scenes.size())
	for i in mini(scenes.size(), 6):
		print("  [", i, "] L", scenes[i]["level"], ": ", scenes[i]["heading"])

	# First "### Scene" (skip ## chapter headings).
	var first_scene := -1
	for i in scenes.size():
		if int(scenes[i]["level"]) == 3:
			first_scene = i
			break
	print("--- first scene entries (index ", first_scene, ") ---")
	var scene_entries: Array = parser.entries_from_scene(entries, first_scene)
	for e in scene_entries:
		match e.get("type"):
			"scene_heading":
				print("HEADING: ", e["text"])
			"dialogue":
				var d := ""
				for dd in e.get("directions", []):
					d += " *[" + dd + "]*"
				print("SAY ", e["character"], d, " :: ", e["text"].left(80))
			"direction":
				print("DIR: ", e["text"].left(80))
			"conditional":
				print("IF: ", e["text"].left(80))
			"trigger":
				print("TRIGGER: ", e["text"].left(80))
			"choice":
				var opts: Array = []
				for o in e["options"]:
					opts.append("(%s) %s %s" % [o["key"], o["text"].left(40), str(o["tags"])])
				print("CHOICE: ", " | ".join(opts))

	# Dialogue box scene load check.
	var packed: PackedScene = load("res://scenes/dialogue_box.tscn")
	if packed:
		var box = packed.instantiate()
		print("dialogue_box.tscn: instantiated OK, nodes: ", box.get_node("Panel/Margin/VBox/HBox/TextLabel").name)
		box.queue_free()
	else:
		print("dialogue_box.tscn: FAILED TO LOAD")
	print("=== TEST DONE ===")
	quit()
