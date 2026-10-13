shader_type canvas_item;

// Removes ONLY the baked mortal longsword blade while an attack is playing.
// The arm, right hand, hilt, armor and cloak stay in the approved painting.
// Companion form1_swing_blade.gdshader samples that exact metal and animates it.
uniform vec2 guard_px = vec2(138.0, 229.0);
uniform vec2 tip_px = vec2(64.0, 342.0);
uniform float frame_left_px = 0.0;
uniform float cut_amount : hint_range(0.0, 1.0) = 0.0;

// Slightly broader near the guard, tapering toward the painted tip.
float blade_mask(vec2 pixel) {
    vec2 origin = mix(guard_px, tip_px, 0.095);
    vec2 length_dir = tip_px - origin;
    float t = clamp(dot(pixel - origin, length_dir) / max(dot(length_dir, length_dir), 1.0), 0.0, 1.0);
    vec2 nearest = origin + t * length_dir;
    float radius = mix(12.0, 2.8, t);
    float shape = 1.0 - smoothstep(max(radius - 2.2, 0.1), radius + 1.4, distance(pixel, nearest));
    // Never cut away the hands, or the tip of a different cell in an atlas.
    float longitudinal = smoothstep(-0.01, 0.065, t) * (1.0 - smoothstep(0.975, 1.03, t));
    return shape * longitudinal;
}

void fragment() {
    vec2 pixel = UV / TEXTURE_PIXEL_SIZE - vec2(frame_left_px, 0.0);
    vec4 paint = texture(TEXTURE, UV);
    paint.a *= 1.0 - blade_mask(pixel) * cut_amount;
    COLOR = paint;
}
