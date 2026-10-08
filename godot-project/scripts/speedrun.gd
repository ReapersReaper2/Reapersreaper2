extends RefCounted
## Reaper's Reaper — Speedrun Mode.
##
## NOTE: intentionally no class_name (project convention — see save_system.gd).
## Static manager; game code passes the GameState node in.
##
## Built-in timer with splits at chapter boundaries. Categories:
##   - any: Any% (reach the ending)
##   - hundred: 100% (all achievements — tracked via Achievements count)
##   - nodeath: No-Death (gravebloomless — zero player deaths)
##
## The timer starts on new game (GameState.new_game) when speedrun mode
## is enabled. Splits fire on chapter changes. Local bests persist per
## category in GameState stats.

const CATEGORIES: Array = ["any", "hundred", "nodeath"]

const CATEGORY_NAMES: Dictionary = {
	"any": "Any%",
	"hundred": "100%",
	"nodeath": "No-Death",
}

## Chapter order for splits. Room chapter prefixes map to split names.
const SPLITS: Array = [
	"prologue", "ch1", "ch2", "ch3", "ch4", "ch5", "ch6",
	"ch7", "ch8", "ch9", "ch10", "ch11", "ch12",
	"ch13", "ch14", "ch15", "ch16", "ch17", "epilogue",
]

const BEST_PREFIX := "speedrun_best_"
const ACTIVE_KEY := "speedrun_active"
const CATEGORY_KEY := "speedrun_category"
const START_KEY := "speedrun_start_msec"
const SPLITS_KEY := "speedrun_splits"


static func is_active(gs) -> bool:
	if gs == null or not gs.has_method("get_stat"):
		return false
	return bool(gs.get_stat(ACTIVE_KEY, false))


static func start_run(gs, category: String) -> bool:
	if gs == null or not gs.has_method("set_stat"):
		return false
	if category not in CATEGORIES:
		return false
	gs.set_stat(ACTIVE_KEY, true)
	gs.set_stat(CATEGORY_KEY, category)
	gs.set_stat(START_KEY, Time.get_ticks_msec())
	gs.set_stat(SPLITS_KEY, {})
	# No-Death: reset the death counter for this run.
	if category == "nodeath":
		gs.set_stat("speedrun_deaths", 0)
	return true


static func stop_run(gs) -> void:
	if gs == null or not gs.has_method("set_stat"):
		return
	gs.set_stat(ACTIVE_KEY, false)


static func elapsed_msec(gs) -> int:
	if not is_active(gs):
		return 0
	var start: int = int(gs.get_stat(START_KEY, 0))
	return Time.get_ticks_msec() - start


static func record_split(gs, chapter: String) -> void:
	## Records a split when the player enters a new chapter.
	if not is_active(gs):
		return
	if chapter not in SPLITS:
		return
	var splits: Dictionary = gs.get_stat(SPLITS_KEY, {})
	if splits.has(chapter):
		return  # Already split here.
	splits[chapter] = elapsed_msec(gs)
	gs.set_stat(SPLITS_KEY, splits)


static func get_splits(gs) -> Dictionary:
	if gs == null or not gs.has_method("get_stat"):
		return {}
	return gs.get_stat(SPLITS_KEY, {})


static func record_death(gs) -> bool:
	## Returns false if this death voids a No-Death run.
	if not is_active(gs):
		return true
	var deaths: int = int(gs.get_stat("speedrun_deaths", 0)) + 1
	gs.set_stat("speedrun_deaths", deaths)
	if str(gs.get_stat(CATEGORY_KEY, "")) == "nodeath":
		stop_run(gs)
		return false
	return true


static func finish_run(gs) -> Dictionary:
	## Called at the ending. Returns {category, time_msec, is_best}.
	var result := {"category": "", "time_msec": 0, "is_best": false}
	if not is_active(gs):
		return result
	var category := str(gs.get_stat(CATEGORY_KEY, "any"))
	var time_msec: int = elapsed_msec(gs)
	stop_run(gs)
	var best_key := BEST_PREFIX + category
	var best: int = int(gs.get_stat(best_key, 0))
	var is_best := best == 0 or time_msec < best
	if is_best:
		gs.set_stat(best_key, time_msec)
	result["category"] = category
	result["time_msec"] = time_msec
	result["is_best"] = is_best
	return result


static func get_best(gs, category: String) -> int:
	if gs == null or not gs.has_method("get_stat"):
		return 0
	return int(gs.get_stat(BEST_PREFIX + category, 0))
