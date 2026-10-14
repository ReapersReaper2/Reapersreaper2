extends SceneTree
## Regression: soul guiding outranks observation on the same touch press,
## and Android says USE even when the touchscreen probe is false.
const Guide := preload("res://scripts/reserve_guide.gd")
var checks := 0
var failed := 0

class FakeGuideRig extends Node:
	var claims := 0
	var should_claim := false
	func try_guide() -> bool:
		claims += 1
		return should_claim

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failed += 1
		push_error("[GARDEN MOBILE GUIDE] " + description)

func _run() -> void:
	_check(Guide.mobile_observation_prompt(true, false) == "USE",
		"native Android USE matches actual touchscreen overlay even if detector fails")
	_check(Guide.mobile_observation_prompt(false, true) == "USE",
		"touch laptop sees USE when an actual touchscreen exists")
	_check(Guide.mobile_observation_prompt(false, false, true) == "USE",
		"editor QA force-touch mode displays correct hint")
	_check(Guide.mobile_observation_prompt(false, false) == "E / INTERACT",
		"keyboard-only mode retains original E hint")

	var mock = FakeGuideRig.new()
	mock.should_claim = true
	_check(Guide.claim_guide_first(mock), "guidable soul wins interaction priority")
	_check(mock.claims == 1, "GuideRig receives action once, not both handlers")
	mock.should_claim = false
	_check(not Guide.claim_guide_first(mock),
		"when no guidable soul claims touch, resident may still be observed")
	_check(mock.claims == 2, "declining guide does not double invoke")
	_check(not Guide.claim_guide_first(null),
		"resident observation survives a missing GuideRig")
	var plain := Node.new()
	_check(not Guide.claim_guide_first(plain),
		"unrelated node cannot consume resident interaction")
	mock.free()
	plain.free()
	if failed == 0:
		print("[GARDEN MOBILE GUIDE] PASS %d checks" % checks)
	else:
		push_error("[GARDEN MOBILE GUIDE] FAIL %d/%d" % [failed, checks])
	quit(1 if failed > 0 else 0)
