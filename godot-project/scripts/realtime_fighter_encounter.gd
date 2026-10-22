extends RefCounted
## DQ-003 stage 2 (slices 1-2): isolated fighter-only real-time encounter core.
## Not wired to the existing tactical BattleManager. No capture actions exist.
## WILT values are intentionally not defined/locked here.
signal fight_ended(outcome: String)
signal actor_killed(actor: RefCounted)

const CombatDamage = preload("res://scripts/combat_damage.gd")

var fighter_hp: int = 3
var fighter_max_hp: int = 3
var fighter_attack: int = 5
var fighter_defense: int = 0
var enemy: Dictionary = {}
var encounter_mode := "fighter_duel"
var allow_flee := true
var active := false
var outcome := ""
var flee_progress := 0.0
var flee_duration := 2.0  # REV 3 §8: wild-fight flee channel
var actor_kill_opt_in := false  # explicit opt-in only; companions never qualify

static func calculate_damage(raw: float, defense: int, incoming_mult: float = 1.0, no_armor: bool = false) -> int:
    return CombatDamage.dealt(raw, defense, incoming_mult, no_armor)

func begin(enemy_fighter: Dictionary, vigor: int = 3, vigor_max: int = 3, wild_fight: bool = true) -> void:
    # Explicit fighter stats/identity, never a fabricated creature BattleUnit.
    assert(str(enemy_fighter.get("role", "")) == "fighter")
    assert(str(enemy_fighter.get("side", "")) == "hostile")
    assert(str(enemy_fighter.get("actor_id", "")) != "")
    var stats: Dictionary = enemy_fighter.get("stats", {})
    for stat in ["vigor", "might", "guard", "speed"]:
        assert(stats.has(stat))
    enemy = enemy_fighter.duplicate(true)
    enemy["hp"] = maxi(1, int(stats["vigor"]))
    allow_flee = wild_fight
    fighter_max_hp = maxi(1, vigor_max)
    fighter_hp = clampi(vigor, 0, fighter_max_hp)
    flee_progress = 0.0
    outcome = ""
    active = fighter_hp > 0
    if not active:
        _finish("defeat")

func fighter_strike(raw: float = -1.0) -> int:
    if not active:
        return 0
    var power := float(fighter_attack) if raw < 0.0 else raw
    var damage := calculate_damage(power, int((enemy["stats"] as Dictionary)["guard"]))
    enemy["hp"] = maxi(0, int(enemy["hp"]) - damage)
    if int(enemy["hp"]) == 0:
        _finish("victory")
    return damage

func enemy_strike(raw: float = -1.0) -> int:
    if not active:
        return 0
    var power := float((enemy["stats"] as Dictionary)["might"]) if raw < 0.0 else raw
    var damage := calculate_damage(power, fighter_defense)
    fighter_hp = maxi(0, fighter_hp - damage)
    flee_progress = 0.0  # damage interrupts an active flee channel
    if fighter_hp == 0:
        _finish("defeat")
    return damage

func advance_flee(delta: float, channel_held: bool) -> void:
    if not active or not allow_flee:
        return
    if not channel_held:
        flee_progress = 0.0
        return
    flee_progress += maxf(0.0, delta)
    if flee_progress >= flee_duration:
        _finish("fled")

func interrupt_flee() -> void:
    flee_progress = 0.0

func force_teardown() -> void:
    if active:
        _finish("forced_teardown")

func _finish(result: String) -> void:
    if not active and outcome != "":
        return
    outcome = result
    active = false
    flee_progress = 0.0
    # Defeat is not the same event as death. Only an explicitly opted-in
    # killable actor may produce actor_killed; never automatic on 0 HP.
    fight_ended.emit(result)
