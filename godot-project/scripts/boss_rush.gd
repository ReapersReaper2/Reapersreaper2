extends RefCounted
## Reaper's Reaper — Boss Rush mode.
##
## NOTE: intentionally no class_name (project convention — see save_system.gd).
## Static manager; game code passes the GameState node in.
##
## All bosses back-to-back, scored. Unlocks after completing the story
## (ending_choice flag set). Uses the existing boss fights via
## BattleManager.start_boss_battle().
##
## Boss roster (in order):
##   1. Tentacle (room_c1 tutorial boss)
##   2. Bellmaw (Gloomy Path)
##   3. Shika Hunters (GD4)
##   4. Harrow (GD5)
##
## Scoring: each boss awards points = max(0, 1000 - seconds*10 - damage_taken*2).
## Total score persists as the local best in GameState.

## Boss id -> {name, creature_id, level, victory_flag}.
const ROSTER: Array = [
	{"id": "tentacle", "name": "The Tentacle", "creature_id": "tentacle", "level": 5, "victory_flag": "rush_tentacle_down"},
	{"id": "bellmaw", "name": "Bellmaw", "creature_id": "bellmaw", "level": 12, "victory_flag": "rush_bellmaw_down"},
	{"id": "shika", "name": "Shika Hunters", "creature_id": "shika_alpha", "level": 20, "victory_flag": "rush_shika_down"},
	{"id": "harrow", "name": "Harrow", "creature_id": "harrow", "level": 25, "victory_flag": "rush_harrow_down"},
]

const UNLOCK_FLAG := "ending_choice"
const BEST_SCORE_KEY := "boss_rush_best"


## Boss Rush unlocks after the story is complete (the Originator's choice made).
static func is_unlocked(gs) -> bool:
	if gs == null or not gs.has_method("get_flag"):
		return false
	return bool(gs.get_flag(UNLOCK_FLAG))


static func roster() -> Array:
	return ROSTER.duplicate()


static func boss_count() -> int:
	return ROSTER.size()


## Score for one boss: faster + less damage = more points.
static func score_boss(seconds: float, damage_taken: int) -> int:
	return maxi(0, int(1000.0 - seconds * 10.0 - float(damage_taken) * 2.0))


static func get_best(gs) -> int:
	if gs == null or not gs.has_method("get_stat"):
		return 0
	return int(gs.get_stat(BEST_SCORE_KEY, 0))


static func submit_score(gs, total: int) -> bool:
	## Returns true if this is a new best.
	if gs == null or not gs.has_method("get_stat"):
		return false
	var best: int = get_best(gs)
	if total > best:
		gs.set_stat(BEST_SCORE_KEY, total)
		return true
	return false
