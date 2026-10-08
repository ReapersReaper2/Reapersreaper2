extends RefCounted
## Reaper's Reaper — Daily Hunts (retention engine).
##
## NOTE: intentionally no class_name (project convention — see save_system.gd).
## Static manager; game code passes the GameState node in.
##
## One rotating bounty per day, the same hunt for everyone: the hunt is
## derived deterministically from the calendar date (YYYY-MM-DD) via a
## stable FNV-1a hash — NOT Godot's String.hash() (not stable across
## platforms) and NOT RandomNumberGenerator state. Same date = same
## target, same level, same modifiers, on every machine. When servers
## land later, this becomes the shared daily without changing the
## generation logic.
##
## Local-first: best clear per date and a local Hall of Fame (the Soul
## Ledger page for daily hunts) persist in GameState stats. No server,
## no global leaderboard yet — the deterministic generation is the
## forward-compat hook.
##
## Modifier application: start_hunt() sets `daily_mod_<id>` stat flags
## for the active hunt's modifiers and clears them on complete/abandon.
## Battle code consumes them via has_modifier(gs, id):
##   no_armor       — battle_unit.take_damage: player Guard soaks nothing (LIVE)
##   bloom_double   — bloom meter gains x2 (future: no bloom system yet)
##   invisible_foes — creature_ai: foes untargetable until first attack (future)
##   frail          — battle_unit.take_damage: incoming damage x2 (LIVE)
##   heavy_hits     — battle_unit: outgoing x1.5, incoming x1.25 (LIVE)
##   slow_start     — battle.gd: player acts last for the first 3 turns (LIVE)
##   rich           — applied in hunt_for(): Soul Credit reward x2 (LIVE)
##   no_items       — battle.gd choose_item: item menu disabled (LIVE)
## Hunt fight wiring (battle_manager.start_daily_hunt_battle -> battle.gd
## tracks duration/damage -> complete_hunt on victory) is LIVE.

## Modifier id -> {name, desc}. Pool of 8; 1-2 picked per day.
const MODIFIERS: Dictionary = {
	"no_armor": {
		"name": "No Armor",
		"desc": "Armor and Guard do nothing today. Dodge or die.",
	},
	"bloom_double": {
		"name": "Bloom Surge",
		"desc": "Bloom builds twice as fast.",
	},
	"invisible_foes": {
		"name": "Unseen",
		"desc": "Enemies are invisible until they attack.",
	},
	"frail": {
		"name": "Frail",
		"desc": "You take double damage.",
	},
	"heavy_hits": {
		"name": "Heavy Hits",
		"desc": "You deal 1.5x damage but take 1.25x.",
	},
	"slow_start": {
		"name": "Slow Start",
		"desc": "You act last for the first 3 turns.",
	},
	"rich": {
		"name": "Rich Veins",
		"desc": "Double Soul Credit rewards.",
	},
	"no_items": {
		"name": "No Provisions",
		"desc": "Items are disabled in battle.",
	},
}

const MODIFIER_IDS: Array = [
	"no_armor", "bloom_double", "invisible_foes", "frail",
	"heavy_hits", "slow_start", "rich", "no_items",
]

## Hunt target pool: 17 wild creatures + 4 boss variants.
## Bosses are rarer (appear ~1 day in 6 by construction of the pool).
const TARGET_POOL: Array = [
	"snapling", "siltmaw", "gravebind", "thornchoir", "bellowscap",
	"wispwillow", "floatbladder", "bloodleaf_grazer", "thornleech",
	"cinderbloom", "echomarrow", "gloomcap", "deepjaw", "spinehopper",
	"dragonthorn", "carrion_bloom", "bellmaw",
	"boss:tentacle", "boss:bellmaw", "boss:shika", "boss:harrow",
]

const BOSS_LEVELS: Dictionary = {
	"boss:tentacle": 8,
	"boss:bellmaw": 14,
	"boss:shika": 22,
	"boss:harrow": 28,
}

## Daily boss target id -> real battle creature id (boss_rush conventions).
const BOSS_CREATURE_IDS: Dictionary = {
	"boss:tentacle": "tentacle",
	"boss:bellmaw": "bellmaw",
	"boss:shika": "shika_alpha",
	"boss:harrow": "harrow",
}


## Map a hunt target_id to the creature id battles spawn.
static func battle_creature_id(target_id: String) -> String:
	if target_id.begins_with("boss:"):
		return str(BOSS_CREATURE_IDS.get(target_id, "bellmaw"))
	return target_id

const BEST_PREFIX := "daily_hunt_best_"
const HOF_KEY := "daily_hunt_hof"
const HOF_SIZE := 20
const ACTIVE_KEY := "daily_hunt_active"
const ACTIVE_DATE_KEY := "daily_hunt_date"
const ACTIVE_MODS_KEY := "daily_hunt_mods"
const ACTIVE_TARGET_KEY := "daily_hunt_target"
const ACTIVE_LEVEL_KEY := "daily_hunt_level"


## Stable FNV-1a 32-bit hash. Deterministic on every platform.
static func fnv1a(text: String) -> int:
	var h: int = 2166136261
	for i in range(text.length()):
		h = h ^ text.unicode_at(i)
		h = (h * 16777619) & 0xFFFFFFFF
	return h


static func date_string(year: int, month: int, day: int) -> String:
	return "%04d-%02d-%02d" % [year, month, day]


static func today_string() -> String:
	var d: Dictionary = Time.get_date_dict_from_system()
	return date_string(int(d.get("year", 1970)), int(d.get("month", 1)), int(d.get("day", 1)))


## The deterministic hunt for a date string ("YYYY-MM-DD").
## {date, target_id, is_boss, target_name, level, modifiers: [...], reward}
static func hunt_for(date_str: String) -> Dictionary:
	var key: String = "reapers-reaper:daily-hunt:" + date_str
	var target: String = TARGET_POOL[fnv1a(key + ":target") % TARGET_POOL.size()]
	var is_boss: bool = target.begins_with("boss:")
	var level: int
	if is_boss:
		level = int(BOSS_LEVELS.get(target, 10))
	else:
		# Wild targets scale 5..30.
		level = 5 + int(fnv1a(key + ":level") % 26)
	var mods: Array = _pick_modifiers(key)
	var reward: int = level * 20
	if is_boss:
		reward *= 2
	if "rich" in mods:
		reward *= 2
	return {
		"date": date_str,
		"target_id": target,
		"is_boss": is_boss,
		"target_name": _target_name(target),
		"level": level,
		"modifiers": mods,
		"reward": reward,
	}


static func _target_name(target_id: String) -> String:
	if target_id.begins_with("boss:"):
		match target_id:
			"boss:tentacle":
				return "The Tentacle"
			"boss:bellmaw":
				return "Bellmaw"
			"boss:shika":
				return "Shika Hunters"
			"boss:harrow":
				return "Harrow"
		return target_id
	# "bloodleaf_grazer" -> "Bloodleaf Grazer"
	var parts: PackedStringArray = target_id.split("_")
	var out: Array = []
	for p in parts:
		out.append(p.capitalize())
	return " ".join(out)


## Pick 1-2 distinct modifiers via salted sub-hashes (well distributed).
static func _pick_modifiers(key: String) -> Array:
	var count: int = 1 + (fnv1a(key + ":modcount") % 2)  # 1 or 2
	var picked: Array = []
	var i: int = 0
	while picked.size() < count and i < 16:
		var mid: String = MODIFIER_IDS[fnv1a(key + ":mod:" + str(i)) % MODIFIER_IDS.size()]
		if mid not in picked:
			picked.append(mid)
		i += 1
	return picked


static func modifier_name(mod_id: String) -> String:
	return str(MODIFIERS.get(mod_id, {}).get("name", mod_id))


static func modifier_desc(mod_id: String) -> String:
	return str(MODIFIERS.get(mod_id, {}).get("desc", ""))


## Score: target level matters most, then speed, then cleanliness.
static func score_hunt(seconds: float, damage_taken: int, level: int) -> int:
	var base: float = float(level) * 100.0
	var time_penalty: float = seconds * 2.0
	var damage_penalty: float = float(damage_taken) * 3.0
	return maxi(0, int(base - time_penalty - damage_penalty))


## --- Active hunt lifecycle --------------------------------------------

static func is_active(gs) -> bool:
	if gs == null or not gs.has_method("get_stat"):
		return false
	return bool(gs.get_stat(ACTIVE_KEY, false))


static func active_hunt(gs) -> Dictionary:
	if not is_active(gs):
		return {}
	return hunt_for(str(gs.get_stat(ACTIVE_DATE_KEY, today_string())))


## Begin today's hunt: records it as active and sets modifier flags.
static func start_hunt(gs, date_str: String = "") -> Dictionary:
	if gs == null or not gs.has_method("set_stat"):
		return {}
	if date_str.is_empty():
		date_str = today_string()
	var hunt: Dictionary = hunt_for(date_str)
	gs.set_stat(ACTIVE_KEY, true)
	gs.set_stat(ACTIVE_DATE_KEY, date_str)
	gs.set_stat(ACTIVE_TARGET_KEY, hunt["target_id"])
	gs.set_stat(ACTIVE_LEVEL_KEY, hunt["level"])
	gs.set_stat(ACTIVE_MODS_KEY, hunt["modifiers"])
	for mid in MODIFIER_IDS:
		gs.set_stat("daily_mod_" + mid, mid in hunt["modifiers"])
	return hunt


static func has_modifier(gs, mod_id: String) -> bool:
	if gs == null or not gs.has_method("get_stat"):
		return false
	return bool(gs.get_stat("daily_mod_" + mod_id, false))


## Resolve today's hunt. Returns {score, is_best, hunt}. Clears active state.
static func complete_hunt(gs, seconds: float, damage_taken: int) -> Dictionary:
	if gs == null or not gs.has_method("set_stat"):
		return {}
	if not is_active(gs):
		return {}
	var date_str: String = str(gs.get_stat(ACTIVE_DATE_KEY, today_string()))
	var hunt: Dictionary = hunt_for(date_str)
	var score: int = score_hunt(seconds, damage_taken, int(hunt["level"]))
	var prev: Dictionary = best_for(date_str, gs)
	var is_best: bool = prev.is_empty() or score > int(prev.get("score", 0))
	if is_best:
		gs.set_stat(BEST_PREFIX + date_str, {
			"score": score,
			"seconds": seconds,
			"damage": damage_taken,
		})
		_push_hall_of_fame(gs, date_str, hunt, score, seconds)
	_clear_active(gs)
	return {"score": score, "is_best": is_best, "hunt": hunt}


static func abandon_hunt(gs) -> void:
	_clear_active(gs)


static func _clear_active(gs) -> void:
	gs.set_stat(ACTIVE_KEY, false)
	gs.set_stat(ACTIVE_DATE_KEY, "")
	gs.set_stat(ACTIVE_MODS_KEY, [])
	for mid in MODIFIER_IDS:
		gs.set_stat("daily_mod_" + mid, false)


## --- Records ----------------------------------------------------------

## Best clear for a date: {score, seconds, damage} or {} if none.
static func best_for(date_str: String, gs) -> Dictionary:
	if gs == null or not gs.has_method("get_stat"):
		return {}
	var b = gs.get_stat(BEST_PREFIX + date_str, {})
	return b if b is Dictionary else {}


## Local Soul Ledger: top clears across all days, newest best first.
## Each entry: {date, target_id, target_name, level, score, seconds}.
static func hall_of_fame(gs) -> Array:
	if gs == null or not gs.has_method("get_stat"):
		return []
	var hof = gs.get_stat(HOF_KEY, [])
	return hof if hof is Array else []


static func _push_hall_of_fame(gs, date_str: String, hunt: Dictionary, score: int, seconds: float) -> void:
	var hof: Array = hall_of_fame(gs)
	# One entry per date: replace the old one if this date re-clears better.
	var fresh: Array = []
	for e in hof:
		if e is Dictionary and str(e.get("date", "")) != date_str:
			fresh.append(e)
	fresh.append({
		"date": date_str,
		"target_id": hunt["target_id"],
		"target_name": hunt["target_name"],
		"level": hunt["level"],
		"score": score,
		"seconds": seconds,
	})
	fresh.sort_custom(func(a, b): return int(a["score"]) > int(b["score"]))
	while fresh.size() > HOF_SIZE:
		fresh.pop_back()
	gs.set_stat(HOF_KEY, fresh)
