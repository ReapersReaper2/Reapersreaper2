extends RefCounted
## Shared DQ-003 damage rule for fighters and creature BattleUnits.
## All constants remain tuning parameters and retain current legacy values.
const GUARD_MITIGATION := 0.6

static func dealt(raw_amount: float, defense: int, incoming_mult: float = 1.0, no_armor: bool = false) -> int:
    var soak := 0.0 if no_armor else float(defense) * GUARD_MITIGATION
    return maxi(1, int(round(raw_amount * incoming_mult - soak)))
