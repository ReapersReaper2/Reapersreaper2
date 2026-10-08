extends SceneTree
## grimley_ivy_test.gd — Grimley/Ivy shared-past content wiring.
## Headless: godot --headless -s scripts/grimley_ivy_test.gd

var _passed := 0
var _failed := 0


func _check(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		printerr("[grimley_ivy_test] FAIL: ", label)


func _read(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var t := f.get_as_text()
	f.close()
	return t


func _init() -> void:
	var g1 := _read("res://scenes/room_g1.tscn")
	var gd3 := _read("res://scenes/room_gd3.tscn")
	var ve := _read("res://scripts/vine_exchange.gd")

	# 1. Ch6 nursery mourning vine cutting (room_g1).
	_check(g1.contains("MourningCutting"), "g1: MourningCutting node present")
	_check(g1.contains("Old argument. Still growing."), "g1: Grimley's exact line present")
	_check(g1.contains("label_text = \"Grimley\""), "g1: cutting attributed to Grimley")
	_check(g1.contains("g1_mourning_vine_seen"), "g1: cutting seen flag present")

	# 2. Petal NPC (room_g1).
	_check(g1.contains("\"Petal\"") or g1.contains("name=\"Petal\""), "g1: Petal NPC present")
	_check(g1.contains("She gave me to him. Before. I don't think he ever told you that."), "g1: Petal's missable line present")
	# Missable: the Ivy line must be in repeat_lines (not first-talk lines),
	# and must NOT set any achievement or journal flag.
	var petal_idx := g1.find("Petal")
	var petal_block := g1.substr(petal_idx, 1200) if petal_idx >= 0 else ""
	_check(petal_block.contains("repeat_lines"), "g1: Petal has repeat_lines (Ivy line missable)")
	_check(not petal_block.contains("achievement"), "g1: Petal sets no achievement")
	_check(not petal_block.contains("journal"), "g1: Petal sets no journal entry")

	# 3. Act 3 ancient vine (room_gd3).
	_check(gd3.contains("AncientVine"), "gd3: AncientVine node present")
	_check(gd3.contains("gd3_ancient_vine_seen"), "gd3: ancient vine seen flag present")
	_check(gd3.contains("She thinks no one is looking"), "gd3: Ivy touch flavor present")

	# 4. Post-game exchange — take points.
	_check(g1.contains("grimley_cutting"), "g1: grimley_cutting item wired")
	_check(gd3.contains("ivy_cutting"), "gd3: ivy_cutting item wired")
	_check(g1.contains("g1_cutting_taken"), "g1: cutting take flag present")
	_check(gd3.contains("gd3_cutting_taken"), "gd3: cutting take flag present")

	# 5. Post-game exchange — delivery points.
	_check(ve != "", "vine_exchange.gd exists")
	_check(g1.contains("DeliverCutting"), "g1: delivery point present")
	_check(gd3.contains("DeliverCutting"), "gd3: delivery point present")
	_check(g1.contains("g1_ivy_cutting_delivered"), "g1: Grimley delivery flag present")
	_check(gd3.contains("gd3_grimley_cutting_delivered"), "gd3: Ivy delivery flag present")
	# Reactions: Grimley quiet, Ivy surprised.
	_check(g1.contains("He says nothing"), "g1: Grimley quiet reaction present")
	_check(gd3.contains("she looks surprised"), "gd3: Ivy surprised reaction present")
	# Post-game gate (no quest marker, but gated on completion).
	_check(g1.contains("e2_fragment_planted"), "g1: exchange gated on post-game")
	_check(gd3.contains("e2_fragment_planted"), "gd3: exchange gated on post-game")

	print("[grimley_ivy_test] done: ", _passed, " passed, ", _failed, " failed")
	quit(1 if _failed > 0 else 0)
