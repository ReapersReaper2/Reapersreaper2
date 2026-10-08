extends Node
## Achievement system for Reaper's Reaper (Steam-ready groundwork).
##
## NOTE: intentionally no class_name (project convention — see save_system.gd).
## Registered as the "Achievements" autoload; game code calls
## Achievements.unlock("bridge_cleared") etc. directly on the singleton.
##
## This is the GAME-SIDE interface. The Steamworks SDK wires in later
## (export pipeline): when it does, _steam_unlock() is the single point
## that starts talking to Steam — everything else stays untouched.
## Until then it just prints, and unlocks persist locally in the save.

signal achievement_unlocked(id: String)

## Launch set. id -> {name, description, hidden}.
const ACHIEVEMENTS: Dictionary = {
	"first_reap": {
		"name": "First Cut",
		"description": "Land your first scythe kill.",
		"hidden": false,
	},
	"bridge_cleared": {
		"name": "First Steps",
		"description": "Clear the invader waves on Bellhollow Bridge.",
		"hidden": false,
	},
	"deathless_p1": {
		"name": "Untouchable",
		"description": "Clear the bridge waves without taking a hit.",
		"hidden": false,
	},
	"collapse_seen": {
		"name": "Witness",
		"description": "Watch the tower fall.",
		"hidden": false,
	},
	"form2_unlocked": {
		"name": "First Form",
		"description": "Unlock Form 2 on the Black Sand Shore.",
		"hidden": false,
	},
	"bounty_done": {
		"name": "Guide",
		"description": "Complete your first bounty: guide a stray soul home.",
		"hidden": false,
	},
	"wisp_guide_10": {
		"name": "Tender",
		"description": "Guide 10 stray souls.",
		"hidden": false,
	},
	"invader_slayer_25": {
		"name": "Reaper's Apprentice",
		"description": "Reap 25 invaders.",
		"hidden": false,
	},
	"invader_slayer_100": {
		"name": "Reaper",
		"description": "Reap 100 invaders.",
		"hidden": true,
	},
	"full_combo": {
		"name": "Twin Arc",
		"description": "Land hits with both swings of a scythe combo.",
		"hidden": false,
	},
	"explorer": {
		"name": "Wanderer",
		"description": "Set foot in every M1 room.",
		"hidden": false,
	},
	"keeper": {
		"name": "Keeper",
		"description": "Save at a Lantern Shrine.",
		"hidden": false,
	},
	"first_catch": {
		"name": "Binder",
		"description": "Catch your first wild creature.",
		"hidden": false,
	},
	"catch_10": {
		"name": "Warden",
		"description": "Catch 10 creatures.",
		"hidden": false,
	},
	"trainer_win": {
		"name": "Duelist",
		"description": "Win your first trainer battle.",
		"hidden": false,
	},
	"bellmaw_win": {
		"name": "Bloom Maw",
		"description": "Defeat Bellmaw on the Gloomy Path.",
		"hidden": false,
	},
	"party_full": {
		"name": "Full House",
		"description": "Fill all 6 party slots.",
		"hidden": false,
	},
	"contractor": {
		"name": "Contractor",
		"description": "Turn in your first bounty board contract.",
		"hidden": false,
	},
	"high_roller": {
		"name": "High Roller",
		"description": "Win 10 games at the Copper Table.",
		"hidden": false,
	},
	"quiet_wisdom": {
		"name": "Quiet Wisdom",
		"description": "Win a game at the Quiet Table.",
		"hidden": false,
	},
	# --- Steam achievement set (story-bot spec, 2026-10-04) ----------------
	# Story (unmissable progression)
	"first_death": {
		"name": "The Knight Falls",
		"description": "Die as a mortal.",
		"hidden": false,
	},
	"reaper_rises": {
		"name": "The Vessel Changes",
		"description": "Earn Form 3 through the willing-reap trial.",
		"hidden": false,
	},
	"armor_born": {
		"name": "Iron and Intent",
		"description": "Take up the blacksmith's armor (Form 4).",
		"hidden": false,
	},
	"green_burial": {
		"name": "What Grows From You",
		"description": "Become the first plant armor (Form 5).",
		"hidden": false,
	},
	"scythe_breaks": {
		"name": "Mount Dragoni",
		"description": "Watch the scythe shatter.",
		"hidden": false,
	},
	"the_hollow": {
		"name": "Severed",
		"description": "Enter the Hollow depowered.",
		"hidden": false,
	},
	"wings": {
		"name": "The Point of No Return",
		"description": "Unfold Form 9 and take first flight.",
		"hidden": false,
	},
	"mirror_broken": {
		"name": "Yourself, Unmade",
		"description": "Defeat Harrow.",
		"hidden": false,
	},
	"the_choice": {
		"name": "Hold or Break",
		"description": "Make the Originator's choice.",
		"hidden": false,
	},
	"return": {
		"name": "Something New Grows",
		"description": "Reach the Tree of Return.",
		"hidden": false,
	},
	# Breeding & creatures
	"first_hatch": {
		"name": "Small Mercies",
		"description": "Hatch your first creature.",
		"hidden": false,
	},
	"spore_harvest": {
		"name": "The Lineage of the Eaten",
		"description": "Harvest a fruit plant grown from a spore-infected kill.",
		"hidden": false,
	},
	"wrong_step": {
		"name": "Wrongness",
		"description": "Hatch a Strange Animal with a Wrongness roll above 80.",
		"hidden": false,
	},
	"dragon_roost": {
		"name": "The Long Hatch",
		"description": "Hatch Flint's dragon egg.",
		"hidden": false,
	},
	"gardener": {
		"name": "Gardener",
		"description": "Breed a second armor plant. The craziest achievement in the game.",
		"hidden": true,
	},
	# Fabricator & systems
	"first_graft": {
		"name": "The Toolbox Wakes",
		"description": "Complete your first living-fabricator graft.",
		"hidden": false,
	},
	"blade_regrown": {
		"name": "It Remembers",
		"description": "Regrow a living-metal blade.",
		"hidden": false,
	},
	"ledger_read": {
		"name": "The Name That Refused",
		"description": "Read Cruliette's glitching ledger entry.",
		"hidden": false,
	},
	"drowned_dice": {
		"name": "Against the Odds",
		"description": "Win a Dead Man's Dice round at maximum stakes.",
		"hidden": false,
	},
	# Challenge
	"clean_hunt": {
		"name": "Survive Cleanly",
		"description": "Complete the tentacle tutorial without taking a hit.",
		"hidden": false,
	},
	"eleven_flowers": {
		"name": "She Counted",
		"description": "Grow eleven graveblooms in one playthrough.",
		"hidden": false,
	},
	"no_bloom_seized": {
		"name": "Quiet Armor",
		"description": "Finish the game without the armor ever seizing a combat turn.",
		"hidden": true,
	},
	# Post-game
	"choki": {
		"name": "The Beast-Master",
		"description": "Begin Choki's legendary thread.",
		"hidden": false,
	},
}

## GameState flags that auto-unlock an achievement when set.
## Checked by cutscene trigger steps (and anything else that sets flags
## through unlock_for_flag). Story beats that unlock via stats or direct
## unlock() calls don't need an entry here.
const FLAG_ACHIEVEMENTS: Dictionary = {
	"p2_collapse_seen": "collapse_seen",
	"p1_bridge_cleared": "bridge_cleared",
	# Steam set: story beats wired through GameState.set_flag.
	# Aligned to the story-bot trigger map (2026-10-04).
	"prologue_complete": "first_death",
	"form3_unlocked": "reaper_rises",
	"form4_unlocked": "armor_born",
	"form5_unlocked": "green_burial",
	"form9_unlocked": "wings",
	"hl1_entered": "the_hollow",
	"harrow_defeated": "mirror_broken",
	"ending_choice": "the_choice",
	"e2_fragment_planted": "return",
	"e1_ledger_read": "ledger_read",
	"scythe_broken": "scythe_breaks",
	"armor_plant_bred": "gardener",
	"tutorial_clean": "clean_hunt",
	"dice_won_max_stakes": "drowned_dice",
	"dragon_hatched": "dragon_roost",
}

# Untyped on purpose: GameState autoload or injected (headless tests).
var game_state = null


func _ready() -> void:
	if game_state == null:
		game_state = get_node_or_null("/root/GameState")


## Unlock an achievement. Idempotent: unlocking twice counts once and
## emits the signal only the first time. Unknown ids warn cleanly.
func unlock(id: String) -> bool:
	if not ACHIEVEMENTS.has(id):
		push_warning("Achievements: unknown achievement id '%s'" % id)
		return false
	if is_unlocked(id):
		return true
	_ledger_achievements().append(id)
	achievement_unlocked.emit(id)
	_steam_unlock(id)
	var entry: Dictionary = ACHIEVEMENTS[id]
	print("[ACHIEVEMENT] unlocked: %s — %s" % [str(entry.get("name", id)), id])
	return true


## Unlock the achievement mapped to a GameState flag, if any.
func unlock_for_flag(flag: String) -> void:
	var id := str(FLAG_ACHIEVEMENTS.get(flag, ""))
	if id != "":
		unlock(id)
	# Hidden "Quiet Armor" (story-bot answers 2026-10-04): if the game
	# ends (o3 ending_choice) and the armor never seized a combat turn
	# this playthrough, it fires here. bloom_seized lives in the
	# GameState flags dict, which new_game() rebuilds — per-playthrough
	# by construction. The armor-seize mechanic (story-bot canon,
	# approved pitch #2, 2026-10-03) sets the flag when it seizes.
	if flag == "ending_choice" and game_state != null and game_state.has_method("get_flag"):
		if not bool(game_state.get_flag("bloom_seized", false)):
			unlock("no_bloom_seized")


func is_unlocked(id: String) -> bool:
	return _ledger_achievements().has(id)


func unlock_count() -> int:
	return _ledger_achievements().size()


func total_count() -> int:
	return ACHIEVEMENTS.size()


## Debug helper: wipe all unlocks (local ledger only).
func reset_all() -> void:
	_ledger_achievements().clear()


## The list of unlocked achievement ids (a live reference into the
## GameState ledger — do not replace it, mutate in place).
func _ledger_achievements() -> Array:
	var gs = _resolve_state()
	if gs == null:
		return _fallback_ledger
	var ledger: Dictionary = gs.get("ledger", {})
	if not ledger.has("achievements"):
		ledger["achievements"] = []
		gs["ledger"] = ledger
	var arr: Array = ledger["achievements"]
	return arr


# Used only when no GameState is available (shouldn't happen in-game).
var _fallback_ledger: Array = []


func _resolve_state():
	if game_state != null and game_state.get("state") is Dictionary:
		return game_state.get("state")
	return null


## STEAMWORKS PLUGS IN HERE.
## When the Steamworks SDK is wired (export pipeline), this function starts
## reporting unlocks to Steam (SteamUserStats.SetAchievement + StoreStats).
## The rest of the game never changes: unlock() stays the single entry point.
func _steam_unlock(id: String) -> void:
	# TODO(steam): SteamUserStats.set_achievement(id); SteamUserStats.store_stats()
	print("[STEAM] achievement hook (no SDK yet): ", id)


## Full-library sync: when the SDK lands, report every locally-unlocked
## achievement (e.g. after reinstall or Steam cloud mismatch). Until then
## it just logs what it would send.
func steam_sync() -> void:
	var ids := _ledger_achievements()
	# TODO(steam): for id in ids: SteamUserStats.set_achievement(id)
	# TODO(steam): SteamUserStats.store_stats()
	print("[STEAM] sync hook (no SDK yet): would report %d unlocks" % ids.size())


# --- Hook-ready notifiers -------------------------------------------------
## These fire achievements for systems that don't exist yet. When each
## system lands, it calls its notifier at the story beat — the unlock,
## persistence, and (later) Steam reporting all flow through unlock().

## Scythe-break system: call when the scythe shatters (Mount Dragoni).
func notify_scythe_break() -> void:
	unlock("scythe_breaks")


## Spore-infection system: call when a fruit plant is harvested from a
## spore-infected kill.
func notify_spore_harvest() -> void:
	unlock("spore_harvest")


## Wrongness system: call when a Strange Animal hatches with a Wrongness
## roll above 80.
func notify_wrong_step() -> void:
	unlock("wrong_step")


## Flint's dragon egg: call when it hatches.
func notify_dragon_roost() -> void:
	unlock("dragon_roost")


## Living-metal system: call when a living-metal blade is regrown.
func notify_blade_regrown() -> void:
	unlock("blade_regrown")


## Gravebloom system: call when the eleventh gravebloom grows in one
## playthrough. NOTE: the gravebloom_grown counter is per-playthrough
## state — the gravebloom system must reset it on new_game().
func notify_eleven_flowers() -> void:
	unlock("eleven_flowers")


## Armor-seize system: call at game finish if the armor never seized a
## combat turn this playthrough. (Hidden achievement.) NOTE: the
## bloom_seized boolean is per-playthrough state — the armor system
## must reset it (false) on new_game().
func notify_no_bloom_seized() -> void:
	unlock("no_bloom_seized")


## Choki's thread: call when Choki's legendary thread begins.
func notify_choki() -> void:
	unlock("choki")
