extends SceneTree
## Run: godot --headless --path godot-project -s res://scripts/realtime_fighter_encounter_test.gd
const Fight = preload("res://scripts/realtime_fighter_encounter.gd")
var failures := 0

func _initialize() -> void:
    call_deferred("_run")

func check(condition: bool, label: String) -> void:
    if condition:
        print("[DQ003] PASS ", label)
    else:
        failures += 1
        push_error("[DQ003] FAIL " + label)

func _run() -> void:
    var win = Fight.new()
    win.begin("snapling", 1)
    check(win.active and win.fighter_hp == 3 and win.fighter_max_hp == 3, "fighter vigor maps to 3 HP")
    for i in range(100):
        win.fighter_strike(1000.0)
        if not win.active:
            break
    check(win.outcome == "victory" and not win.active, "victory tears down")
    var lose = Fight.new()
    lose.begin("snapling", 1)
    lose.enemy_strike(1000.0)
    check(lose.outcome == "defeat" and lose.fighter_hp == 0, "Mollosar defeat")
    var flee = Fight.new()
    flee.begin("snapling", 1)
    flee.advance_flee(0.7, true)
    flee.enemy_strike(1.0)
    check(flee.active and is_zero_approx(flee.flee_progress), "hit interrupts flee channel")
    flee.advance_flee(flee.flee_duration + 0.1, true)
    check(flee.outcome == "fled", "completed flee resolves")
    var forced = Fight.new()
    forced.begin("snapling", 1)
    forced.force_teardown()
    check(forced.outcome == "forced_teardown" and not forced.active, "forced teardown")
    forced.force_teardown()
    check(forced.outcome == "forced_teardown", "forced teardown idempotent")
    check(Fight.calculate_damage(5.0, 5) == maxi(1, int(round(5.0 - 5.0 * 0.6))), "damage math aligns with BattleUnit")
    print("[DQ003] ", "PASS" if failures == 0 else "FAIL", " failures=", failures)
    quit(0 if failures == 0 else 1)
