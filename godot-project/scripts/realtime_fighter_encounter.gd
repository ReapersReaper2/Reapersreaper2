extends RefCounted
## DQ-003 stage 2 (slices 1-2): isolated fighter-only real-time encounter core.
## Not wired to the existing tactical BattleManager. No capture actions exist.
## WILT values are intentionally not defined/locked here.
signal fight_ended(outcome: String)
signal actor_killed(actor: RefCounted)

const BattleUnit = preload("res://scripts/battle_unit.gd")
const CombatDamage = preload("res://scripts/combat_damage.gd")

var fighter_hp: int = 3
var fighter_max_hp: int = 3
var fighter_attack: int = 5
var fighter_defense: int = 0
var enemy: RefCounted
var active := false
var outcome := ""
var flee_progress := 0.0
var flee_duration := 1.5  # provisional parameter, not a design lock
var actor_kill_opt_in := false  # explicit opt-in only; companions never qualify

static func calculate_damage(raw: float, defense: int, incoming_mult: float = 1.0, no_armor: bool = false) -> int:
    return CombatDamage.dealt(raw, defense, incoming_mult, no_armor)

func begin(field_enemy_id: String, level: int, vigor: int = 3, vigor_max: int = 3) -> void:
    enemy = BattleUnit.new(field_enemy_id, level)
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
    var damage := calculate_damage(power, int(enemy.effective_defense()))
    enemy.hp = maxi(0, enemy.hp - damage)
    if enemy.hp == 0:
        enemy.fainted = true
        _finish("victory")
    return damage

func enemy_strike(raw: float = -1.0) -> int:
    if not active:
        return 0
    var power := float(enemy.effective_attack()) if raw < 0.0 else raw
    var damage := calculate_damage(power, fighter_defense)
    fighter_hp = maxi(0, fighter_hp - damage)
    flee_progress = 0.0  # damage interrupts an active flee channel
    if fighter_hp == 0:
        _finish("defeat")
    return damage

func advance_flee(delta: float, channel_held: bool) -> void:
    if not active:
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
