extends RefCounted
## Soul Vault: creature storage for Reaper's Reaper tactical battles.
##
## NAME NOTE: the story docs never name creature storage (the Soul Council
## "vault" is a dungeon, not creature storage). "Soul Vault" is a wiring
## placeholder — the story bot can canon-name it later; only VAULT_NAME and
## the UI title need to change.
##
## Boxes persist in GameState.state["storage"]: an Array of BOX_COUNT boxes,
## each an Array of up to BOX_SIZE creature entries (same dict shape as party
## entries: {creature_id, level, xp, current_hp, nickname, ability_ids}).
##
## No class_name / autoload on purpose: consumers preload this script, so it
## works in headless -s test scripts too (autoloads don't load there).
##   const Storage = preload("res://scripts/storage.gd")
##
## Mutable state lives in GameState and is passed in as `gs` — the module
## itself holds no mutable state (same pattern as party.gd).

const Party = preload("res://scripts/party.gd")

const VAULT_NAME := "Soul Vault"
const BOX_COUNT := 8  # tuning placeholder
const BOX_SIZE := 30  # tuning placeholder


## The raw storage array in GameState (created empty when the key is
## missing; each box is created lazily).
static func _storage(gs: Node) -> Array:
	if not gs.state.has("storage"):
		gs.state["storage"] = []
	return gs.state["storage"]


## The live Array for box `bi` (created empty when missing). [] when invalid.
static func _box(gs: Node, bi: int) -> Array:
	if bi < 0 or bi >= BOX_COUNT:
		return []
	var s: Array = _storage(gs)
	while s.size() <= bi:
		s.append([])
	return s[bi]


static func is_valid_box(bi: int) -> bool:
	return bi >= 0 and bi < BOX_COUNT


## Number of occupied slots in box `bi`.
static func box_count(gs: Node, bi: int) -> int:
	return _box(gs, bi).size()


## Entry dict at (bi, si), or {} when invalid.
static func get_entry(gs: Node, bi: int, si: int) -> Dictionary:
	var b := _box(gs, bi)
	if si < 0 or si >= b.size():
		return {}
	return b[si]


## First free [box, slot] across all boxes, or [-1, -1] when the vault
## is completely full. Slot = b.size() (append-only packing).
static func first_free_slot(gs: Node) -> Array:
	for bi in BOX_COUNT:
		if _box(gs, bi).size() < BOX_SIZE:
			return [bi, _box(gs, bi).size()]
	return [-1, -1]


## Deposit a ready-made creature entry dict. Returns [box, slot], or
## [-1, -1] when full. Used by battle catches that bypass the party.
static func deposit_entry(gs: Node, entry: Dictionary) -> Array:
	if entry.is_empty():
		return [-1, -1]
	var spot := first_free_slot(gs)
	if spot[0] < 0:
		return spot
	_box(gs, spot[0]).append(entry)
	return spot


## Move party member `pi` into the vault. Returns [box, slot], or
## [-1, -1] when the vault is full.
static func deposit(gs: Node, pi: int) -> Array:
	var entry: Dictionary = Party.get_entry(gs, pi)
	if entry.is_empty():
		return [-1, -1]
	var spot := first_free_slot(gs)
	if spot[0] < 0:
		push_warning("Storage: vault full, cannot deposit '%s'" % str(entry.get("creature_id")))
		return spot
	_box(gs, spot[0]).append(entry.duplicate())
	Party.remove_creature(gs, pi)
	return spot


## Withdraw the entry at (bi, si) into the party. False (no write) when
## the party is full or the slot is empty.
static func withdraw(gs: Node, bi: int, si: int) -> bool:
	var b := _box(gs, bi)
	if si < 0 or si >= b.size():
		return false
	if Party.size(gs) >= Party.MAX_SIZE:
		push_warning("Storage: party full, cannot withdraw from box %d slot %d" % [bi, si])
		return false
	var entry: Dictionary = (b[si] as Dictionary).duplicate()
	b.remove_at(si)
	if not Party.add_creature(gs, str(entry.get("creature_id")), int(entry.get("level"))):
		# Shouldn't happen (we checked size), but never lose a creature.
		b.insert(si, entry)
		return false
	# Restore the entry's real xp/HP instead of the fresh make_entry values.
	var added: Dictionary = Party.get_entry(gs, Party.size(gs) - 1)
	for k in entry.keys():
		added[k] = entry[k]
	return true


## Swap two slots inside one box. False when either index is invalid.
static func move_within_box(gs: Node, bi: int, a: int, si_b: int) -> bool:
	var b := _box(gs, bi)
	if a < 0 or a >= b.size() or si_b < 0 or si_b >= b.size():
		return false
	var tmp: Dictionary = b[a]
	b[a] = b[si_b]
	b[si_b] = tmp
	return true


## Move an entry from (from_bi, from_si) to another box's end (or a swap
## when the target slot is occupied). False when invalid or the target
## box is full and the target slot is out of range.
static func move_between_boxes(gs: Node, from_bi: int, from_si: int, to_bi: int, to_si: int) -> bool:
	var fb := _box(gs, from_bi)
	var tb := _box(gs, to_bi)
	if from_si < 0 or from_si >= fb.size():
		return false
	if to_si < 0 or to_si > tb.size() or tb.size() >= BOX_SIZE:
		return false
	var entry: Dictionary = fb[from_si]
	fb.remove_at(from_si)
	# Removing from the same box shifts the target index down.
	if from_bi == to_bi and from_si < to_si:
		to_si -= 1
	if to_si >= tb.size():
		tb.append(entry)
	else:
		tb.insert(to_si, entry)
	return true


## Release (delete) the entry at (bi, si). No confirmation here — the UI
## asks before calling. Returns the released entry dict (for the log).
static func release(gs: Node, bi: int, si: int) -> Dictionary:
	var b := _box(gs, bi)
	if si < 0 or si >= b.size():
		return {}
	var entry: Dictionary = b[si]
	b.remove_at(si)
	return entry


## True when the whole vault has no free slot.
static func is_full(gs: Node) -> bool:
	return first_free_slot(gs)[0] < 0


## Total creatures stored across all boxes.
static func total_stored(gs: Node) -> int:
	var n := 0
	for bi in BOX_COUNT:
		n += _box(gs, bi).size()
	return n


## Fresh-game storage: empty boxes are created lazily, so nothing to do —
## kept for symmetry with Party.new_game_party and future migration needs.
static func new_game_storage(_gs: Node) -> void:
	pass
