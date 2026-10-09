extends Node
## Live game state for Reaper's Reaper.
##
## NOTE: intentionally no class_name (see save_system.gd — Godot 4.3
## forbids class_name matching the autoload name). Registered as the
## "GameState" autoload; game code uses the GameState singleton.
##
## Gameplay code reads/writes `state` here; only SaveSystem touches files.
## Autoload order in project.godot: SaveSystem first, then GameState, so
## _ready() can resolve /root/SaveSystem. save_system may also be injected
## (used by headless tests where autoloads are not loaded).

const SaveSystemScript := preload("res://scripts/save_system.gd")
const WeaponDataScript := preload("res://scripts/weapon_data.gd")

const PartyScript := preload("res://scripts/party.gd")
const DepowerScript := preload("res://scripts/depower.gd")
const ScytheBreak := preload("res://scripts/scythe_break.gd")
const SpeedrunScript := preload("res://scripts/speedrun.gd")
## Step driver (state["run"] step clock; spec STEP-DRIVER-SPEC REV 2 §2-§4).
const StepDriver := preload("res://scripts/step_driver.gd")

var state: Dictionary = {}
var save_system = null
# Achievements autoload, or injected (headless tests where autoloads
# aren't loaded — same pattern as save_system above).
var achievements = null

## Emitted after load_from_slot replaces the live state — listeners that
## mirror state (Stats) re-pull here.
signal state_loaded


func _ready() -> void:
	if save_system == null:
		save_system = get_node_or_null("/root/SaveSystem")
	if achievements == null:
		achievements = get_node_or_null("/root/Achievements")
	if state.is_empty():
		new_game()


func new_game() -> void:
	state = SaveSystemScript.default_save()
	# Step clock: every new game gets a real run_id/started_at (the
	# default_save() placeholder zeros are never what a live run carries).
	StepDriver.reset_run(self)
	# The scythe starts unlocked; Ch12-14 unlocks the rest via story events.
	for wid in WeaponDataScript.starting_weapons():
		WeaponDataScript.unlock(self, wid)
	# Starter creature: a lv5 snapling.
	PartyScript.new_game_party(self)
	# Starting catch supplies.
	add_item("soul_snare", STARTING_SNARES)
	# A couple of basic heals so the ITEM menu isn't empty at first (docs §6:
	# poultices are sold everywhere basics are sold; tuning placeholder).
	add_item("grave_moss_poultice", 2)
	# Starting Soul Credits (tuning placeholder; docs don't specify).
	state["soul_credits"] = STARTING_CREDITS
	# Speedrun mode: if enabled via settings, start the timer on new game.
	if bool(ProjectSettings.get_setting("reaper/speedrun_mode", false)):
		var category := str(ProjectSettings.get_setting("reaper/speedrun_category", "any"))
		SpeedrunScript.start_run(self, category)


func save_to_slot(slot: int) -> bool:
	if save_system == null:
		push_error("GameState: no SaveSystem available")
		return false
	return save_system.save_game(slot, state)


func load_from_slot(slot: int) -> bool:
	if save_system == null:
		push_error("GameState: no SaveSystem available")
		return false
	var data: Dictionary = save_system.load_game(slot)
	if data.is_empty():
		return false
	state = data
	# Step clock (C3): upgrade the migrated "" run_id sentinel to a real
	# identity and field-wise repair the run section before anything
	# reads it — not only on first step.
	StepDriver.ensure_run(self)
	state_loaded.emit()
	return true


func has_save(slot: int) -> bool:
	return save_system != null and save_system.has_save(slot)


## The manual-save slot Lantern Shrines write to (slots 1-3 per
## SaveSystem.MANUAL_SLOTS). Persisted in the save payload itself.
func get_current_slot() -> int:
	return int(state.get("current_slot", 1))


func set_current_slot(slot: int) -> void:
	state["current_slot"] = slot


## Manual save at a Lantern Shrine (shrines wire to this later).
func save_shrine(slot: int) -> bool:
	if save_system == null:
		push_error("GameState: no SaveSystem available")
		return false
	# Keeper first: the payload must capture the unlock.
	_ach_unlock("keeper")
	return save_system.save_shrine(slot, state)


## Achievement hook (null-safe: headless tests have no Achievements).
func _ach_unlock(id: String) -> void:
	if achievements != null and achievements.has_method("unlock"):
		achievements.unlock(id)


## Public unlock wrapper for systems that hold a GameState reference
## (breeding, fabricator, dice). Null-safe.
func unlock_achievement(id: String) -> void:
	_ach_unlock(id)


## Player defeat (Vigor 0): a gravebloom grows where Mollosar fell
## (canon: graveblooms grow ONLY from player defeats, doc 03b; Ivy's
## "I counted the flowers" line is the canonical counter, per the
## story-bot answers 2026-10-04). Per-playthrough counter — the flags
## dict is rebuilt in new_game(), so it resets automatically.
func on_player_defeat() -> void:
	var grown := bump_counter("gravebloom_grown")
	if grown >= 11:
		unlock_achievement("eleven_flowers")
	# Speedrun: a death voids a No-Death run.
	SpeedrunScript.record_death(self)


## Chapter autosave.
func chapter_autosave() -> bool:
	if save_system == null:
		push_error("GameState: no SaveSystem available")
		return false
	return save_system.chapter_autosave(state)


# --- Flag helpers -------------------------------------------------------

func set_flag(flag: String, value: bool = true) -> void:
	(state["flags"] as Dictionary)[flag] = value
	# Story-beat achievements keyed off flags (mirror_broken, armor_born,
	# green_burial, ledger_read, the_choice...). Idempotent and null-safe.
	if value and achievements != null and achievements.has_method("unlock_for_flag"):
		achievements.unlock_for_flag(flag)
	# Scythe-break (Ch12 d2 summit): swap to the longsword/fairy moveset.
	if flag == ScytheBreak.FLAG_BROKEN and value:
		ScytheBreak.on_break(self)
	# Restoration (U3, depower fully lifts): scythe returns, longsword
	# becomes a keepsake. Clear the broken flag so the phase ends.
	if flag == ScytheBreak.FLAG_REPOWERED and value:
		ScytheBreak.on_restore(self)
		(state["flags"] as Dictionary).erase(ScytheBreak.FLAG_BROKEN)


func get_flag(flag: String, default: bool = false) -> bool:
	return bool((state["flags"] as Dictionary).get(flag, default))


func clear_flag(flag: String) -> void:
	(state["flags"] as Dictionary).erase(flag)


# --- Stat helpers (speedrun, boss rush, etc.) ------------------------------

func set_stat(key: String, value) -> void:
	if not state.has("stats"):
		state["stats"] = {}
	(state["stats"] as Dictionary)[key] = value


func get_stat(key: String, default = null):
	if not state.has("stats"):
		return default
	return (state["stats"] as Dictionary).get(key, default)


## Numeric counters in the flags dict (achievement trigger maps use
## counters: creature_hatched, graft_completed...). Separate from the
## boolean flags above; does NOT fire unlock_for_flag.
func bump_counter(key: String) -> int:
	var flags: Dictionary = state["flags"]
	var v := int(flags.get(key, 0)) + 1
	flags[key] = v
	return v


func get_counter(key: String) -> int:
	return int((state["flags"] as Dictionary).get(key, 0))


## Journal ledger: creatures the player has encountered ("seen") or caught.
## Stored as state["seen_creatures"] (Array of ids). Caught implies seen.
func mark_seen(creature_id: String) -> void:
	if not state.has("seen_creatures"):
		state["seen_creatures"] = []
	var seen: Array = state["seen_creatures"]
	if not seen.has(creature_id):
		seen.append(creature_id)


func has_seen(creature_id: String) -> bool:
	return (state.get("seen_creatures", []) as Array).has(creature_id)


func get_seen() -> Array:
	return (state.get("seen_creatures", []) as Array).duplicate()


# --- Player helpers -----------------------------------------------------

func set_position(room: String, x: float, y: float) -> void:
	var pos: Dictionary = (state["player"] as Dictionary)["position"]
	pos["room"] = room
	pos["x"] = x
	pos["y"] = y


func get_position() -> Dictionary:
	return (state["player"] as Dictionary)["position"]


## Ch13-14 depower: forms 3+ are locked while fully depowered; partial
## repower allows form 3 (weak plant abilities) only. Requests for a
## locked form are refused (the current form is kept) so story beats
## can't accidentally power the player up mid-depower. Callers that
## need to know can check Depower.can_use_form() first.
func set_form(form: int) -> void:
	if not DepowerScript.can_use_form(self, form):
		print("[DEPOWER] form %d refused (depowered)" % form)
		return
	(state["player"] as Dictionary)["form"] = form
	# Form milestones: whichever system grants the form (willing-reap
	# trial, blacksmith, bloom tutorial...), the achievement fires here.
	match form:
		3:
			_ach_unlock("reaper_rises")
		4:
			_ach_unlock("armor_born")
		5:
			_ach_unlock("green_burial")


func get_form() -> int:
	return int((state["player"] as Dictionary).get("form", 1))


func set_vigor(vigor: int, vigor_max: int = -1) -> void:
	var p: Dictionary = state["player"]
	p["vigor"] = vigor
	if vigor_max >= 0:
		p["vigor_max"] = vigor_max


func add_playtime(delta: float) -> void:
	state["playtime"] = float(state.get("playtime", 0.0)) + delta


# --- Last shrine (blackout respawn) --------------------------------------
## Set by shrine.gd on rest. Battle defeat ("black out") respawns here.

func set_last_shrine(room_id: String, x: float, y: float) -> void:
	state["last_shrine"] = {"room": room_id, "x": x, "y": y}


func get_last_shrine() -> Dictionary:
	return state.get("last_shrine", {"room": "p1", "x": 0.0, "y": 0.0})


## Lantern Shrine fast-travel network. A shrine joins the network the
## first time the player rests at it. Value: {shrine_id: {"room": room_id,
## "x": x, "y": y}} — position is captured at rest time so travel can
## spawn the player at the shrine. Persists in the save payload.
func light_shrine(shrine_id: String, room_id: String, x: float, y: float) -> void:
	var lit: Dictionary = state.get("shrines_lit", {})
	lit[shrine_id] = {"room": room_id, "x": x, "y": y}
	state["shrines_lit"] = lit


func get_lit_shrines() -> Dictionary:
	return state.get("shrines_lit", {})


func heal_to_full() -> void:
	var p: Dictionary = state["player"]
	p["vigor"] = int(p.get("vigor_max", p.get("vigor", 1)))


# --- Soul Credits (currency) ----------------------------------------------
## Canon name from 04-items-crafting.md: "The economy is souls. Soul
## Credits are the currency." Old saves fall back to 0 via .get().
## Starting amount is wiring-side tuning (docs don't specify one).

const STARTING_CREDITS := 300

func get_soul_credits() -> int:
	return int(state.get("soul_credits", 0))


func add_soul_credits(n: int) -> void:
	state["soul_credits"] = maxi(0, get_soul_credits() + n)


## Spend credits. Returns false (no write) when funds are insufficient.
func spend_soul_credits(n: int) -> bool:
	if get_soul_credits() < n:
		return false
	state["soul_credits"] = get_soul_credits() - n
	return true


# --- Inventory -----------------------------------------------------------
## Item counts live in state["inventory"] ({item_id: count}). Soul Snares
## (the catch item) are granted on new_game; shops/loot are later work.

const STARTING_SNARES := 5

func _inventory() -> Dictionary:
	if not state.has("inventory") or not (state["inventory"] is Dictionary):
		state["inventory"] = {}
	return state["inventory"]


func get_item_count(item_id: String) -> int:
	return int(_inventory().get(item_id, 0))


func add_item(item_id: String, n: int = 1) -> void:
	var inv := _inventory()
	inv[item_id] = maxi(0, int(inv.get(item_id, 0)) + n)


## Consume one item. Returns false (no write) when none are held.
func use_item(item_id: String) -> bool:
	var inv := _inventory()
	var n := int(inv.get(item_id, 0))
	if n <= 0:
		return false
	inv[item_id] = n - 1
	return true
