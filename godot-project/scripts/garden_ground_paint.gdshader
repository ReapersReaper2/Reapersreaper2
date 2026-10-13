shader_type canvas_item;

// Two original Muse-made 512x512 textures. UV scales to world metres so
// the terrain has the same texture scale across all three Reserve rooms.
uniform sampler2D grass_texture : source_color, repeat_enable, filter_linear_mipmap;
uniform sampler2D path_texture : source_color, repeat_enable, filter_linear_mipmap;
uniform sampler2D trail_mask : filter_linear;
uniform vec2 world_tiling = vec2(2.5, 1.40625);
uniform float dusk_saturation : hint_range(0.0, 1.0) = 0.90;

void fragment() {
	vec2 tiled = UV * world_tiling;
	vec4 grass = texture(grass_texture, tiled);
	vec4 path = texture(path_texture, tiled);
	float path_weight = smoothstep(0.0, 1.0, texture(trail_mask, UV).r);
	vec3 paint = mix(grass.rgb, path.rgb, path_weight);
	// Keep the original palette, slightly calm the blue highlights.
	float luma = dot(paint, vec3(0.299, 0.587, 0.114));
	paint = mix(vec3(luma), paint, dusk_saturation);
	COLOR = vec4(paint, 1.0);
}
