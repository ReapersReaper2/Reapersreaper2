extends RefCounted
## Reaper's Reaper — UI text database.
##
## Loads canon UI strings from data/ui_text.json (snapshot of doc 08
## §7 supplement, "In-Game Text Database"). Covers store descriptions,
## merchant disposition tiers, haggling/investing lines, creature family
## Ledger headers, rearing text, and Night Market strings.
##
## When the story bot updates doc 08, re-snapshot the supplement into
## data/ui_text.json (same shape). Accessors below never crash on
## missing keys — they return "" so UI degrades gracefully.

const UI_TEXT_PATH := "res://data/ui_text.json"

static var _cache: Dictionary = {}


static func _load() -> Dictionary:
	if not _cache.is_empty():
		return _cache
	if not FileAccess.file_exists(UI_TEXT_PATH):
		return {}
	var f := FileAccess.open(UI_TEXT_PATH, FileAccess.READ)
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		_cache = parsed
	return _cache


## Store description by key (e.g. "oddments", "the_forge"). Returns "" if unknown.
static func store_desc(key: String) -> String:
	var stores: Dictionary = _load().get("stores", {})
	var entry: Dictionary = stores.get(key, {})
	return str(entry.get("desc", ""))


## Store display name by key. Returns "" if unknown.
static func store_name(key: String) -> String:
	var stores: Dictionary = _load().get("stores", {})
	var entry: Dictionary = stores.get(key, {})
	return str(entry.get("name", ""))


## Merchant disposition line by tier key (stranger/regular/friend/partner).
static func disposition_desc(tier: String) -> String:
	var tiers: Dictionary = _load().get("disposition", {})
	var entry: Dictionary = tiers.get(tier, {})
	return str(entry.get("desc", ""))


## Creature family Ledger header by key.
static func family_desc(key: String) -> String:
	var fams: Dictionary = _load().get("families", {})
	var entry: Dictionary = fams.get(key, {})
	return str(entry.get("desc", ""))


## Haggling / investing / night market one-liners by label.
static func haggle(label: String) -> String:
	return str(_load().get("haggling", {}).get(label, ""))


static func invest(label: String) -> String:
	return str(_load().get("investing", {}).get(label, ""))


static func night_market(label: String) -> String:
	return str(_load().get("night_market", {}).get(label, ""))


## Feeding-loop prompt/line by label (e.g. "eat_prompt",
## "luna_smell_necrolean"). Verbatim lines locked by Sweet Potato Creature
## (collab log 2026-10-05) — wiring side never paraphrases. Returns "" if
## unknown.
static func feeding(label: String) -> String:
	return str(_load().get("feeding", {}).get(label, ""))
