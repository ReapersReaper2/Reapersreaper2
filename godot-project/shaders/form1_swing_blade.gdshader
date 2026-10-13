shader_type canvas_item;

// The attacking blade is sampled from the approved Form 1 WALK texture,
// never a newly drawn generic weapon. Rotate its painted metal around the
// right-hand guard. Base sprite shader hides the original resting metal.
uniform vec2 guard_px = vec2(138.0, 229.0);
uniform vec2 tip_px = vec2(64.0, 342.0);
uniform float frame_left_px = 0.0;
uniform float swing_angle_radians = 0.0;
uniform float opacity : hint_range(0.0, 1.0) = 0.0;

float blade_mask(vec2 pixel) {
    vec2 origin = mix(guard_px, tip_px, 0.095);
    vec2 length_dir = tip_px - origin;
    float t = clamp(dot(pixel - origin, length_dir) / max(dot(length_dir, length_dir), 1.0), 0.0, 1.0);
    vec2 nearest = origin + t * length_dir;
    float radius = mix(12.0, 2.8, t);
    float shape = 1.0 - smoothstep(max(radius - 2.2, 0.1), radius + 1.4, distance(pixel, nearest));
    float longitudinal = smoothstep(-0.01, 0.065, t) * (1.0 - smoothstep(0.975, 1.03, t));
    return shape * longitudinal;
}

void fragment() {
    vec2 destination = UV / TEXTURE_PIXEL_SIZE - vec2(frame_left_px, 0.0);
    float c = cos(swing_angle_radians);
    float s = sin(swing_angle_radians);
    vec2 offset = destination - guard_px;
    // Inverse mapping: destination pixel -> its original painted sword pixel.
    vec2 source = guard_px + vec2(
        c * offset.x + s * offset.y,
       -s * offset.x + c * offset.y
    );
    if (source.x < 0.0 || source.x >= 384.0 || source.y < 0.0 || source.y >= 384.0) {
        COLOR = vec4(0.0);
    } else {
        vec2 source_uv = (source + vec2(frame_left_px, 0.0)) * TEXTURE_PIXEL_SIZE;
        vec4 art = texture(TEXTURE, source_uv);
        art.a *= blade_mask(source) * opacity;
        COLOR = art;
    }
}
