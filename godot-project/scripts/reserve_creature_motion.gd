extends RefCounted
## Deterministic, sprite-only ambient motion for living Reserve residents.
## Pure math: no RNG per frame, save writes, collisions, or capture effects.
## The visible resident stays anchored near its authored home position.
##
## These are presentation styles, not creature temperament or battle AI.
enum Style { ROOTED, DRIFT, HOP, PROWL }

const MAX_WANDER := 40.0
const MAX_LIFT := 34.0

static func sample(style: int, elapsed: float, phase_seed: float = 0.0,
		attention: float = 0.0) -> Dictionary:
	var t := maxf(0.0, elapsed)
	var p := t + phase_seed
	var side := 0.0
	var forward := 0.0
	var lift := 0.0
	var tilt := 0.0
	var breath := 0.0

	match style:
		Style.DRIFT:
			# A hovering, living presence: two incommensurate cycles prevent
			# the same mechanical figure-eight from repeating every few seconds.
			side = sin(p * 0.53) * 17.0
			forward = sin(p * 0.31 + 0.8) * 9.0
			lift = 5.0 + 5.0 * (0.5 + 0.5 * sin(p * 0.82))
			tilt = sin(p * 0.65) * 0.065
			breath = sin(p * 1.10) * 0.035
		Style.HOP:
			# Hops come between long rests. Both ends of the leap meet
			# ground at zero height, so there is no position teleport.
			var period := 3.2
			var cycle := fposmod(t + phase_seed * 0.27, period) / period
			if cycle >= 0.32 and cycle <= 0.65:
				var u := (cycle - 0.32) / 0.33
				lift = sin(PI * u) * 27.0
			side = sin(p * 0.67) * 15.0
			forward = sin(p * 0.41) * 5.0
			tilt = sin(p * 1.25) * 0.028 + (lift / 27.0) * 0.035
			breath = sin(p * 1.6) * 0.025
		Style.PROWL:
			# Confident slow steps, still constrained to a small territory;
			# this is not navigation or an attack behavior.
			side = sin(p * 0.68) * 23.0
			forward = sin(p * 0.37 + 0.2) * 10.0
			lift = maxf(0.0, sin(p * 2.2)) * 3.5
			tilt = sin(p * 0.68) * 0.045
			breath = sin(p * 1.20) * 0.028
		_:
			# Rooted residents must still breathe and settle, without
			# wandering away from their authored garden positions.
			side = sin(p * 0.42) * 3.0
			forward = sin(p * 0.36 + 1.2) * 2.0
			lift = 0.0
			tilt = sin(p * 0.38) * 0.037
			breath = sin(p * 0.86) * 0.045

	var aware := clampf(attention, 0.0, 1.0)
	# Recognition is visible as a tiny lean, not an involuntary capture.
	tilt += sin(p * 2.4) * 0.018 * aware
	breath += aware * 0.018
	# Keep every style near its home point, preserving room clearances.
	var offset := Vector2(side, forward - lift)
	offset = offset.limit_length(MAX_WANDER)
	return {
		"offset": offset,
		"lift": clampf(lift, 0.0, MAX_LIFT),
		"tilt": clampf(tilt, -0.14, 0.14),
		"breath": clampf(breath, -0.07, 0.085),
	}
