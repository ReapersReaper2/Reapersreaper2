extends SceneTree
## Focused headless wayfinding QA (no artwork download required).
## godot --headless --path godot-project --script res://scripts/reserve_wayfinding_test.gd

const Guide := preload("res://scripts/reserve_guide.gd")
const Arrow := preload("res://scripts/reserve_compass_arrow.gd")
const Resident := preload("res://scripts/reserve_creature.gd")

class FakeState:
	extends Node
	var state: Dictionary = {"reserve_observed": []}

var _checks := 0
var _failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var entries: Array = [
		{"id": "gloomcap", "name": "GLOOMCAP", "position": Vector2(100, 0)},
		{"id": "dragonthorn", "name": "DRAGONTHORN", "position": Vector2(-100, 0)},
		{"id": "wispwillow", "name": "WISPWILLOW", "position": Vector2(900, 0)}
	]
	var target: Dictionary = Guide.choose_unobserved(Vector2.ZERO, entries, [])
	_check(target.get("id", "") == "dragonthorn",
		"equal-distance targets break ties by stable species ID")
	_check(Guide.choose_unobserved(Vector2.ZERO, entries, ["dragonthorn"]).get("id", "") == "gloomcap",
		"previously observed species never becomes the active objective")
	_check(Guide.choose_unobserved(Vector2.ZERO, entries, ["gloomcap", "dragonthorn"]).get("id", "") == "wispwillow",
		"compass moves to the next remaining observation")
	_check(Guide.choose_unobserved(Vector2.ZERO, entries,
		["gloomcap", "dragonthorn", "wispwillow"]).is_empty(),
		"compass has no target after every resident is seen")
	_check(Guide.choose_unobserved(Vector2(850, 0), entries, []).get("id", "") == "wispwillow",
		"compass responds to the player's position rather than spawn point")
	_check(Guide.choose_unobserved(Vector2.ZERO, [
		{"id": "bad", "position": "broken"}, entries[0]], []).get("id", "") == "gloomcap",
		"malformed resident entries do not crash or hijack guidance")
	_check(Guide.distance_hint(169.0) == "NEARBY" and Guide.distance_hint(170.0) == "AHEAD",
		"nearby distance threshold behaves predictably")
	_check(Guide.distance_hint(489.0) == "AHEAD" and Guide.distance_hint(490.0) == "FARTHER",
		"farther distance threshold behaves predictably")

	var arrow = Arrow.new()
	arrow.name = "CompassArrow"
	root.add_child(arrow)
	_check(arrow.mouse_filter == Control.MOUSE_FILTER_IGNORE,
		"compass never steals mobile touches")
	_check(not arrow.is_active(), "compass is hidden until a target exists")
	arrow.point_to(Vector2(0, -250))
	_check(arrow.is_active() and arrow.direction().is_equal_approx(Vector2.UP),
		"target north means the arrow points up")
	arrow.point_to(Vector2(50, 0))
	_check(arrow.direction().is_equal_approx(Vector2.RIGHT),
		"target east means the arrow points right")
	arrow.point_to(Vector2(-50, 50))
	_check(arrow.direction().x < -0.5 and arrow.direction().y > 0.5,
		"diagonal world directions map to matching on-screen arrows")
	arrow.clear()
	_check(not arrow.is_active(), "clearing the last target hides the arrow")
	arrow.queue_free()

	# Integration: the existing ReserveGuide picks only living residents,
	# without adding quest state, changing player movement or writing save.
	var room := Node2D.new()
	room.name = "ReserveWayfindingFixture"
	root.add_child(room)
	var player := CharacterBody2D.new()
	player.name = "Player"
	player.position = Vector2(0, 0)
	room.add_child(player)
	var creatures := Node2D.new()
	creatures.name = "Creatures"
	room.add_child(creatures)
	var art := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	art.fill(Color(0.2, 0.5, 0.3, 1.0))
	var sample_tex := ImageTexture.create_from_image(art)
	var near = Resident.new()
	near.name = "Gloomcap"
	near.texture = sample_tex
	near.position = Vector2(75, 0)
	creatures.add_child(near)
	var far = Resident.new()
	far.name = "Dragonthorn"
	far.texture = sample_tex
	far.position = Vector2(350, 0)
	creatures.add_child(far)
	var guide = Guide.new()
	guide.name = "ReserveGuide"
	room.add_child(guide)
	var fake_state := FakeState.new()
	room.add_child(fake_state)
	guide._game_state = fake_state
	guide._update_hud()
	_check(guide.get("_last_guided_id") == "gloomcap",
		"initial live waypoint chooses the nearest unobserved resident")
	_check((guide.get("_waypoint_arrow") as Control).has_method("point_to") and
		(guide.get("_waypoint_arrow") as Control).call("is_active"),
		"live HUD contains an active compass")
	fake_state.state["reserve_observed"] = ["gloomcap"]
	guide._update_hud()
	_check(guide.get("_last_guided_id") == "dragonthorn",
		"observation ledger updates the live compass target")
	fake_state.state["reserve_observed"] = ["gloomcap", "dragonthorn"]
	guide._update_hud()
	_check(str((guide.get("_waypoint_label") as Label).text).is_empty() and
		not bool((guide.get("_waypoint_arrow") as Control).call("is_active")),
		"completed observation objective clears the live arrow and hint")
	_check((guide.get("_status") as Label).text.contains("continue along the trail"),
		"completed observation objective offers neutral onward guidance")
	room.queue_free()

	if _failures == 0:
		print("[RESERVE WAYFINDING] PASS %d checks" % _checks)
	else:
		push_error("[RESERVE WAYFINDING] FAILED %d/%d" % [_failures, _checks])
	quit(1 if _failures > 0 else 0)

func _check(ok: bool, description: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		push_error("[RESERVE WAYFINDING] " + description)
