extends RefCounted
## Memories — the memory-currency economy.
##
## Mollosar's flashbacks are finite and spendable. Canon (06b, Astral
## Village): the innkeeper trades one memory for a night's rest ("it's
## gone. Not suppressed. Gone."); the elder warns "spend your remaining
## memories wisely. They're the only currency that matters."
##
## Storage: flags on GameState (the source of truth).
##   `flashback_gone_<key>` — memory spent (traded or projected), gone
##     permanently. Never cleared.
##   `memory_traded` — the one-time inn trade happened.
##   `projection_unlocked` — Whisper-line taught (06b scene 3, old woman).
##   `projection_active` — a projection is currently running (stats hold
##     `projection_memory_key` and `projection_until_msec`).
##
## Design constraints (for future content):
## - Memories CANNOT be farmed. There are exactly 6. Spending one is a
##   real, permanent decision.
## - Projection-gated dungeon content must be OPTIONAL or completable
##   without projection — a player at 0 memories must never soft-lock.
##
## NOTE: intentionally no class_name (project convention). Load via preload.

## Canonical flashbacks, in the order the inn scene surfaces them.
## The inn trade offers the first four (A-D); bell_tower and bridge are
## named in the scene's flashback list but not offered.
const MEMORIES := {
	"horsemen": {
		"name": "The Horsemen",
		"desc": "Armored men on horseback, riding out of the smoke.",
	},
	"church_bells": {
		"name": "The Church Bells",
		"desc": "Bells tolling over a town that is already gone.",
	},
	"silver_helmet": {
		"name": "The Silver Helmet",
		"desc": "A silver helmet on an empty saddle.",
	},
	"invaders": {
		"name": "The Invaders",
		"desc": "Boats on the black water. Fire on the shore.",
	},
	"bell_tower": {
		"name": "The Bell Tower",
		"desc": "Climbing stone steps that never seemed to end.",
	},
	"bridge": {
		"name": "The Bridge",
		"desc": "A bridge, and something waiting on the other side.",
	},
}

## Inn-trade choice letters (06b: "Trade a memory — (A)/(B)/(C)/(D)").
const TRADE_OPTIONS := {
	"A": "horsemen",
	"B": "church_bells",
	"C": "silver_helmet",
	"D": "invaders",
}

## How long a projection lasts once cast (Whisper-line: attention,
## stretched thin — it cannot hold long).
const PROJECTION_DURATION_MSEC := 30000


static func _gone_flag(key: String) -> String:
	return "flashback_gone_" + key


## Memory keys the player still holds, in canonical order.
static func owned(gs) -> Array:
	var out: Array = []
	for key in MEMORIES.keys():
		if gs != null and gs.has_method("get_flag"):
			if bool(gs.get_flag(_gone_flag(key), false)):
				continue
		out.append(key)
	return out


static func count(gs) -> int:
	return owned(gs).size()


static func has(gs, key: String) -> bool:
	return MEMORIES.has(key) and owned(gs).has(key)


static func gone(gs, key: String) -> bool:
	return MEMORIES.has(key) and not has(gs, key)


static func memory_name(key: String) -> String:
	if MEMORIES.has(key):
		return str((MEMORIES[key] as Dictionary).get("name", key))
	return key


static func memory_desc(key: String) -> String:
	if MEMORIES.has(key):
		return str((MEMORIES[key] as Dictionary).get("desc", ""))
	return ""


## Spend a memory permanently. Returns false when not owned (fail-safe:
## nothing is spent, nothing is flagged).
static func spend(gs, key: String) -> bool:
	if not MEMORIES.has(key):
		push_warning("memories: unknown memory '%s'" % key)
		return false
	if not has(gs, key):
		return false
	if gs != null and gs.has_method("set_flag"):
		gs.set_flag(_gone_flag(key), true)
	return true


## The inn trade: spend + record that the one-time transaction happened.
static func trade(gs, key: String) -> bool:
	if not spend(gs, key):
		return false
	if gs != null and gs.has_method("set_flag"):
		gs.set_flag("memory_traded", true)
	return true


## Map an inn-choice letter ("A".."D") to a memory key ("" when unknown).
static func trade_key_for_letter(letter: String) -> String:
	return str(TRADE_OPTIONS.get(letter.to_upper(), ""))


## Tradeable options filtered to memories the player still holds.
## Returns [{letter, key, name}] for the inn choice UI.
static func trade_options(gs) -> Array:
	var out: Array = []
	for letter in TRADE_OPTIONS.keys():
		var key := str(TRADE_OPTIONS[letter])
		if has(gs, key):
			out.append({"letter": letter, "key": key, "name": memory_name(key)})
	return out


## --- Projection (Whisper-line) --------------------------------------------

static func projection_unlocked(gs) -> bool:
	if gs != null and gs.has_method("get_flag"):
		return bool(gs.get_flag("projection_unlocked", false))
	return false


static func can_project(gs) -> bool:
	return projection_unlocked(gs) and count(gs) > 0


## Project a memory: replay the flashback one last time, then burn it.
## Sets the projection state (30s). Returns the memory dict for the
## replay, or {} when the projection cannot start.
static func project(gs, key: String) -> Dictionary:
	if not projection_unlocked(gs):
		return {}
	if not spend(gs, key):
		return {}
	if gs != null and gs.has_method("set_flag"):
		gs.set_flag("projection_active", true)
	if gs != null and gs.has_method("set_stat"):
		gs.set_stat("projection_memory_key", key)
		gs.set_stat("projection_until_msec", Time.get_ticks_msec() + PROJECTION_DURATION_MSEC)
	return MEMORIES[key]


## Which memory was projected ("" when none).
static func projection_memory(gs) -> String:
	if gs != null and gs.has_method("get_stat"):
		return str(gs.get_stat("projection_memory_key", ""))
	return ""


## True while a projection is running. Auto-clears on expiry.
static func projection_active(gs) -> bool:
	if gs == null or not gs.has_method("get_flag"):
		return false
	if not bool(gs.get_flag("projection_active", false)):
		return false
	var until := 0
	if gs.has_method("get_stat"):
		until = int(gs.get_stat("projection_until_msec", 0))
	if until > 0 and Time.get_ticks_msec() >= until:
		end_projection(gs)
		return false
	return true


static func end_projection(gs) -> void:
	if gs != null and gs.has_method("set_flag"):
		gs.set_flag("projection_active", false)
