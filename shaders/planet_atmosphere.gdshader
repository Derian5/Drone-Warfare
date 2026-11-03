shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled;

uniform vec3 glow_color : source_color = vec3(0.35, 0.6, 1.0);
uniform float strength = 1.4;
uniform float sharpness = 3.0;

void fragment() {
	float rim = 1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	ALBEDO = glow_color * pow(rim, sharpness) * strength;
}
