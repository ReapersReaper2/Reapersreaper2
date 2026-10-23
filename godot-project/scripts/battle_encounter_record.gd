extends RefCounted
## DQ-003 / REV 3 §7 explicit encounter record contract.
## Identity and combat role are independent of species. Producers and battle
## config readers must pass this shape without silently dropping fields.
const MODES := ["fighter_duel", "companion_skirmish", "side_duel", "peaceful"]
const SIDES := ["player", "hostile", "neutral"]
const ROLES := ["fighter", "companion"]

static func make_combatant(actor_id: String, side: String, role: String, stats: Dictionary = {}, species_id: String = "") -> Dictionary:
    assert(not actor_id.is_empty())
    assert(SIDES.has(side))
    assert(ROLES.has(role))
    if role == "fighter":
        for stat in ["vigor", "might", "guard", "speed"]:
            assert(stats.has(stat))
    return {
        "actor_id": actor_id,
        "side": side,
        "role": role,
        "species_id": species_id,
        "stats": stats.duplicate(true)
    }

static func make_record(mode: String, player_fighter: Dictionary, enemy_fighter: Dictionary, enemy_creatures: Array = []) -> Dictionary:
    assert(MODES.has(mode))
    assert(str(player_fighter.get("side", "")) == "player")
    assert(str(player_fighter.get("role", "")) == "fighter")
    assert(str(enemy_fighter.get("side", "")) == "hostile")
    assert(str(enemy_fighter.get("role", "")) == "fighter")
    if mode == "fighter_duel":
        assert(enemy_creatures.is_empty(), "fighter_duel is fighter-only")
    return {
        "mode": mode,
        "player_fighter": player_fighter.duplicate(true),
        "enemy_fighter": enemy_fighter.duplicate(true),
        "enemy_creatures": enemy_creatures.duplicate(true),
        "combatants": [player_fighter.duplicate(true), enemy_fighter.duplicate(true)]
    }

static func manager_pending(record: Dictionary, return_room: String, return_pos: Vector2, victory_flag: String = "") -> Dictionary:
    assert(MODES.has(str(record.get("mode", ""))))
    var enemy: Dictionary = record.get("enemy_fighter", {})
    return {
        "mode": record["mode"],
        "player_fighter": record["player_fighter"].duplicate(true),
        "enemy_fighter": enemy.duplicate(true),
        "enemy_fighter_stats": (enemy.get("stats", {}) as Dictionary).duplicate(true),
        "enemy_creatures": (record.get("enemy_creatures", []) as Array).duplicate(true),
        "combatants": (record.get("combatants", []) as Array).duplicate(true),
        "victory_flag": victory_flag,
        "return_room": return_room,
        "return_pos": return_pos
    }
