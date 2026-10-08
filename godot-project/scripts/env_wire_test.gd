extends SceneTree

var rooms := {
    "gd1": "gd1-garden-perimeter.png",
    "gd2": "gd2-wraths-corner.png",
    "gd4": "gd4-ascent.png",
    "gd5": "gd5-harrow.png",
    "gd6": "gd6-battlefield.png",
    "gd7": "gd7-driftcap-ship.png",
    "o2": "o2-originator-domain.png",
    "o3": "o3-choice-chamber.png",
    "t2": "t2-rite.png",
    "t3": "t3-empty-chair.png",
    "t4": "t4-necrofruit-vault.png",
    "t6": "t6-portal.png",
    "u3": "u3-wings.png",
    "u4": "u4-launch.png",
    "e1": "e1-ledger.png",
    "e2": "e2-tree-of-return.png",
    "hl1": "hl1-black-shore.png",
    "hl2": "hl2-long-walk.png",
    "hl3": "hl3-watchers.png",
    "hl4": "hl4-stairs.png",
    "t1": "t1-temple-gate.png",
    "t5": "t5-marrows-chamber.png",
    "u1": "u1-strangling.png",
    "u2": "u2-absorption.png",
    "gd3": "gd3-ivys-sanctum.png",
    "gd8": "gd8-deep-roots.png",
    "o1": "o1-the-climb.png",
}

var passed := 0
var failed := 0

func _check(name: String, cond: bool) -> void:
    if cond:
        passed += 1
        print("  PASS: " + name)
    else:
        failed += 1
        print("  FAIL: " + name)

func _init() -> void:
    print("[TEST] env-wire: 27 M4 rooms background art (o1 panel wired)")
    for room in rooms:
        var panel: String = rooms[room]
        var scene: PackedScene = load("res://scenes/room_%s.tscn" % room)
        _check("%s scene loads" % room, scene != null)
        if scene == null:
            continue
        var inst: Node = scene.instantiate()
        _check("%s instantiates" % room, inst != null)
        var bg: Node = inst.get_node_or_null("Background")
        _check("%s has Background node" % room, bg != null)
        if bg != null and bg is Sprite2D:
            var tex: Texture2D = (bg as Sprite2D).texture
            _check("%s Background has texture" % room, tex != null)
            if tex != null:
                _check("%s texture has size" % room, tex.get_width() > 0 and tex.get_height() > 0)
        # art file exists on disk
        _check("%s panel file exists" % room, FileAccess.file_exists("res://assets/environments/" + panel))
        inst.queue_free()
    print("[TEST] env-wire: %d passed, %d failed (of %d)" % [passed, failed, passed + failed])
    quit(0 if failed == 0 else 1)
