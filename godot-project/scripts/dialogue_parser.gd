extends RefCounted
class_name DialogueParser
## Parses Reaper's Reaper dialogue scripts (docs 06a/06b/06c) into
## structured data for the dialogue box UI.
##
## Supported conventions (matched to the actual 06a format):
## - `## Chapter` / `### Scene N: title`  -> {type:"scene_heading", level, text}
## - `**CHARACTER:** line`                 -> {type:"dialogue", character, character_note, text, directions}
## - `**NAME (note):** line`               -> character_note holds the parenthetical
## - `*[stage direction]*` (own line)      -> {type:"direction", text}
## - `*[If (A): ...]*`                     -> {type:"conditional", text} (choice consequence note)
## - `[TRIGGER: ...]` (own line)          -> {type:"trigger", text}
## - `> **Choice:** (A) "x" [tag] / ...`  -> {type:"choice", options:[{key,text,tags}]}
## Inline `*[...]*` inside a dialogue line is extracted into that entry's
## `directions` array and removed from the spoken text. Plain `*word*`
## emphasis is left untouched in the text.
## Blank lines and `---` separators are skipped.


## Parse raw script text into an Array of Dictionaries.
static func parse(text: String) -> Array:
	var entries: Array = []
	var heading_re := RegEx.new()
	heading_re.compile("^(#{2,3})\\s+(.*)$")
	var dialogue_re := RegEx.new()
	dialogue_re.compile("^\\*\\*([^*]+?):\\*\\*\\s?(.*)$")
	var inline_dir_re := RegEx.new()
	inline_dir_re.compile("\\*\\[([^\\]]*)\\]\\*")
	var name_note_re := RegEx.new()
	name_note_re.compile("^(.+?)\\s*\\(([^)]+)\\)$")

	for raw_line in text.split("\n"):
		var line := raw_line.strip_edges()
		if line.is_empty() or line == "---":
			continue

		# Scene / chapter headings.
		var hm := heading_re.search(line)
		if hm:
			entries.append({
				"type": "scene_heading",
				"level": hm.get_string(1).length(),
				"text": hm.get_string(2).strip_edges(),
			})
			continue

		# Triggers (bare `[TRIGGER: ...]` or italic-wrapped `*[TRIGGER: ...]*`
		# as used in 06b/06c).
		var trig_text := _parse_trigger_line(line)
		if trig_text != "":
			entries.append({"type": "trigger", "text": trig_text})
			continue

		# Choices.
		if line.begins_with(">"):
			var choice := _parse_choice_line(line)
			if not choice.is_empty():
				entries.append(choice)
				continue

		# Dialogue lines.
		var dm := dialogue_re.search(line)
		if dm:
			var name_part := dm.get_string(1).strip_edges()
			var spoken := dm.get_string(2).strip_edges()
			var character := name_part
			var note := ""
			var nm := name_note_re.search(name_part)
			if nm:
				character = nm.get_string(1).strip_edges()
				note = nm.get_string(2).strip_edges()
			var directions: Array = []
			for im in inline_dir_re.search_all(spoken):
				directions.append(im.get_string(1).strip_edges())
			spoken = inline_dir_re.sub(spoken, "", true).strip_edges()
			# Collapse double spaces left by removed directions.
			while spoken.contains("  "):
				spoken = spoken.replace("  ", " ")
			entries.append({
				"type": "dialogue",
				"character": character,
				"character_note": note,
				"text": spoken,
				"directions": directions,
			})
			continue

		# Standalone italic lines: stage directions or conditional notes.
		if line.begins_with("*[") and line.ends_with("]*"):
			var inner := line.substr(2, line.length() - 4).strip_edges()
			if inner.begins_with("If (") or inner.begins_with("If("):
				entries.append({"type": "conditional", "text": inner})
			else:
				entries.append({"type": "direction", "text": inner})
			continue

		# Anything else (doc title, meta italics like *Part 1 of 3*) is
		# kept as a direction so no content is silently dropped.
		if line.begins_with("#"):
			continue
		entries.append({"type": "direction", "text": line})

	return entries


## Parse a script file from disk.
static func parse_file(path: String) -> Array:
	if not FileAccess.file_exists(path):
		push_error("DialogueParser: file not found: " + path)
		return []
	var f := FileAccess.open(path, FileAccess.READ)
	var text := f.get_as_text()
	f.close()
	return parse(text)


## Return [{heading, index}] for every scene/chapter heading in order.
static func get_scenes(entries: Array) -> Array:
	var scenes: Array = []
	for i in entries.size():
		var e: Dictionary = entries[i]
		if e.get("type") == "scene_heading":
			scenes.append({"heading": e.get("text"), "level": e.get("level"), "index": i})
	return scenes


## Return entries from the scene at scene_index up to (not incl.) the next heading.
static func entries_from_scene(entries: Array, scene_index: int) -> Array:
	var scenes := get_scenes(entries)
	if scene_index < 0 or scene_index >= scenes.size():
		return []
	var start: int = scenes[scene_index]["index"]
	var end: int = entries.size()
	if scene_index + 1 < scenes.size():
		end = scenes[scene_index + 1]["index"]
	return entries.slice(start, end)


## Extract trigger text from a `[TRIGGER: ...]` line, bare or wrapped in a
## single italic span (`*[TRIGGER: ...]*` as used in 06b/06c). Returns ""
## when the line is not a trigger. Nested brackets (e.g. inner [WIRING:])
## are preserved: the outer wrapper is stripped procedurally, not by regex.
static func _parse_trigger_line(line: String) -> String:
	var s := line
	# 06b/06c wrap the whole trigger in one italic span: *[TRIGGER: ...]*.
	# The span markers are the outer asterisks only — the [TRIGGER:] brackets
	# are content, not markers.
	if s.length() >= 2 and s.begins_with("*") and s.ends_with("*"):
		s = s.substr(1, s.length() - 2).strip_edges()
	if s.begins_with("[TRIGGER:") and s.ends_with("]"):
		return s.substr("[TRIGGER:".length(), s.length() - "[TRIGGER:".length() - 1).strip_edges()
	return ""


## Parse one `> **Choice:** ...` line into a choice entry (or {} if invalid).
static func _parse_choice_line(line: String) -> Dictionary:
	var body := line.substr(1).strip_edges()  # drop '>'
	if body.begins_with("**Choice:**"):
		body = body.substr("**Choice:**".length()).strip_edges()
	elif body.begins_with("**Choice**:"):
		body = body.substr("**Choice**:".length()).strip_edges()
	else:
		return {}
	var options: Array = []
	var key_re := RegEx.new()
	key_re.compile("^\\(([A-Za-z0-9]+)\\)\\s*(.*)$")
	var tags_re := RegEx.new()
	tags_re.compile("^(.*?)\\s*((?:\\[[^\\]]+\\]\\s*)*)$")
	var tag_each_re := RegEx.new()
	tag_each_re.compile("\\[([^\\]]+)\\]")
	for part in body.split(" / "):
		var p := part.strip_edges()
		if p.is_empty():
			continue
		var km := key_re.search(p)
		if not km:
			# Leading prompt before the first option, e.g.
			# "Trade a memory — (A) The horsemen." — re-anchor at the key.
			var inner_re := RegEx.new()
			inner_re.compile("\\(([A-Za-z0-9]+)\\)")
			var im := inner_re.search(p)
			if im:
				p = p.substr(im.get_start())
				km = key_re.search(p)
			if not km:
				continue
		var rest := km.get_string(2).strip_edges()
		var tags: Array = []
		var gm := tags_re.search(rest)
		var opt_text := rest
		if gm:
			opt_text = gm.get_string(1).strip_edges()
			for t in tag_each_re.search_all(gm.get_string(2)):
				tags.append(t.get_string(1).strip_edges())
		# Strip surrounding quotes (straight or curly).
		if opt_text.length() >= 2:
			var first := opt_text[0]
			var last := opt_text[opt_text.length() - 1]
			if (first == '"' and last == '"') or (first == "\u201c" and last == "\u201d"):
				opt_text = opt_text.substr(1, opt_text.length() - 2)
		options.append({"key": km.get_string(1), "text": opt_text, "tags": tags})
	if options.is_empty():
		return {}
	return {"type": "choice", "options": options}
