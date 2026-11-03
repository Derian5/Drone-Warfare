shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, shadows_disabled;

uniform sampler2D clouds : filter_linear_mipmap, repeat_enable;
uniform float opacity : hint_range(0.0, 1.0) = 0.75;
uniform vec3 cloud_color : source_color = vec3(1.0);

varying vec3 local_normal;

void vertex() {
	local_normal = normalize(VERTEX);
}

void fragment() {
	vec3 n = normalize(local_normal);
	vec2 uv = vec2(atan(n.x, n.z) / (2.0 * PI) + 0.5, 0.5 - asin(clamp(n.y, -1.0, 1.0)) / PI);
	float c = texture(clouds, uv).r;
	ALBEDO = cloud_color;
	ALPHA = c * opacity;
	ROUGHNESS = 1.0;
}
