extends RefCounted
## P2 — tower-collapse cutscene (Bellhollow Bridge east end).
##
## NOTE: intentionally no class_name (project convention). room_p1.gd
## preloads this and feeds steps() to the cutscene player.
##
## Dialogue is 06a canon (Prologue Sc2). The structure (beats, camera,
## rumble, fade, flag, transition) is the wiring contract.

static func steps() -> Array:
	return [
		{"type": "letterbox", "on": true, "time": 0.6},
		{"type": "dialogue", "lines": [
			{"type": "direction", "text": "The tower groans overhead. Stone screams against stone."},
			{"type": "dialogue", "character": "MOLLOSAR",
				"text": "The bridge is giving way — move!"},
		]},
		# Look back west across the bridge as it starts to fail.
		{"type": "camera", "to": Vector2(-600, 0), "time": 2.5},
		{"type": "sfx", "name": "tower_collapse"},
		{"type": "rumble", "trauma": 0.85, "time": 1.6},
		{"type": "dialogue", "lines": [
			{"type": "direction", "text": "The tower collapses. Dust swallows the bridge whole."},
			{"type": "dialogue", "character": "MOLLOSAR",
				"text": "No… the village—"},
		]},
		# Luna isn't staged in this beat; the new scene sets up its own.
		{"type": "luna", "active": false},
		{"type": "fade", "to": 1.0, "time": 1.2},
		{"type": "trigger", "flag": "p2_collapse_seen"},
		# Steam: "first_death" — the mortal-death cutscene completes.
		# (trigger map: prologue_complete flag)
		{"type": "trigger", "flag": "prologue_complete"},
		{"type": "scene", "path": "res://scenes/room_p3.tscn",
			"room": "p3", "spawn": Vector2(-1000, 200)},
	]
