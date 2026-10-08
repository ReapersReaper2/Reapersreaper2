extends Camera2D
## Trauma-based screen shake. Call add_trauma() on hits; trauma decays and
## the offset follows noise * trauma^2, so small hits stay subtle and only
## stacked/heavy hits punch. Runs on unscaled delta on purpose: the shake
## keeps breathing through hitstop instead of freezing with it.

@export var max_offset: float = 14.0
@export var decay_rate: float = 1.8
@export var shake_speed: float = 30.0

## 0.0 (still) .. 1.0 (max shake).
var trauma: float = 0.0

var _t: float = 0.0
var _noise: FastNoiseLite = FastNoiseLite.new()


func add_trauma(amount: float) -> void:
	trauma = clampf(trauma + amount, 0.0, 1.0)


func _process(delta: float) -> void:
	if trauma <= 0.0:
		if offset != Vector2.ZERO:
			offset = Vector2.ZERO
		return
	trauma = maxf(0.0, trauma - decay_rate * delta)
	_t += delta * shake_speed
	var s: float = trauma * trauma
	offset = Vector2(_noise.get_noise_1d(_t), _noise.get_noise_1d(_t + 131.7)) * max_offset * s
