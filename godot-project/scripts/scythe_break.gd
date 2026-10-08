extends RefCounted
## Scythe-break and longsword phase manager for Reaper's Reaper.
##
## Canon: Ch12 at Mount Dragoni summit (room_d2) the scythe shatters.
## Ch13-14 Mollosar fights with his father's longsword (fairy-touched
## moveset). At U3 (ch13_repowered) the scythe is restored and the
## longsword becomes a cosmetic keepsake.
##
## No class_name / autoload on purpose: consumers preload this script, so it
## works in headless -s test scripts too (autoloads don't load there).
##   const ScytheBreak = preload("res://scripts/scythe_break.gd")
##
## Wiring: GameState.set_flag() calls on_break() when "scythe_broken" is
## set, and on_restore() when "ch13_repowered" is set. The d2 SummitBoss
## lore object sets scythe_broken via extra_flags; the u3 Form 9 gate sets
## ch13_repowered via extra_flags.

const WeaponData = preload("res://scripts/weapon_data.gd")

## Flag set at the d2 summit break.
const FLAG_BROKEN := "scythe_broken"
## Flag set at U3 when depower fully lifts (restoration beat).
const FLAG_REPOWERED := "ch13_repowered"
## Item id for the father's longsword (picked up in room_f3, but granted
## here as a fallback if the break happens without it).
const ITEM_LONGSWORD := "fathers_longsword"


## The scythe shatters. Swap to the longsword/fairy moveset, grant the
## longsword item if missing, and trigger the break visual on the player.
## Idempotent: safe to call twice (the flag check in set_flag guards it,
## but tests and edge cases may call directly).
static func on_break(gs: Node) -> void:
	if gs == null:
		return
	# Edge case: player somehow lacks the longsword — grant it.
	if gs.has_method("get_item_count") and gs.has_method("add_item"):
		if int(gs.get_item_count(ITEM_LONGSWORD)) <= 0:
			gs.add_item(ITEM_LONGSWORD, 1)
	# Swap to the longsword/fairy moveset (thinner, weaker — the
	# "thinner, more desperate" Ch13-14 feel from the sound brief).
	if gs.get("state") != null:
		WeaponData.set_current(gs, WeaponData.WEAPON_LONGSWORD, WeaponData.POWER_FAIRY)
	# Visual break sequence on the live player (no-op in headless tests).
	_play_break_visual(gs)
	print("[SCYTHE] broke — longsword phase begins")


## The scythe is restored at U3. Swap back to scythe/armor; the longsword
## stays in inventory as a cosmetic keepsake (no combat function).
static func on_restore(gs: Node) -> void:
	if gs == null:
		return
	if gs.get("state") != null:
		WeaponData.set_current(gs, WeaponData.WEAPON_SCYTHE, WeaponData.POWER_ARMOR)
	print("[SCYTHE] restored — longsword is a keepsake now")


## True while the longsword phase is active.
static func is_broken(gs: Node) -> bool:
	if gs == null or not gs.has_method("get_flag"):
		return false
	return bool(gs.get_flag(FLAG_BROKEN, false))


## Best-effort visual: find the live player and play the break sequence.
## Silent no-op when there's no scene tree (headless tests).
static func _play_break_visual(gs: Node) -> void:
	if not gs.is_inside_tree():
		return
	var tree: SceneTree = gs.get_tree()
	if tree == null:
		return
	var player: Node = tree.get_first_node_in_group("player")
	if player != null and player.has_method("play_scythe_break"):
		player.play_scythe_break()
