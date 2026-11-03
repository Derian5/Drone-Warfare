shader_type spatial;
render_mode specular_schlick_ggx;

// Planet surface for the orbital region. Paint textures/regions/05_orbit/surface.png
// (equirectangular, RGB) and city_lights.png (white = lights on the night side).
uniform sampler2D surface : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D city_lights : filter_linear_mipmap, repeat_enable;
uniform vec3 light_color : source_color = vec3(1.0, 0.8, 0.45);
uniform float lights_strength = 1.6;
uniform float ocean_gloss : hint_range(0.0, 1.0) = 0.55;
uniform float grid_lines : hint_range(0.0, 1.0) = 0.12;
uniform vec4 grid_color : source_color = vec4(0.5, 0.8, 1.0, 1.0);
uniform float brightness = 1.0;

varying vec3 local_normal;

void vertex() {
	local_normal = normalize(VERTEX);
}

void fragment() {
	vec3 n = normalize(local_normal);
	float lon = atan(n.x, n.z);
	float lat = asin(clamp(n.y, -1.0, 1.0));
	vec2 uv = vec2(lon / (2.0 * PI) + 0.5, 0.5 - lat / PI);
	vec3 col = texture(surface, uv).rgb;
	float ocean = step(col.b, col.r + 0.05) < 0.5 && col.b > col.g ? 1.0 : 0.0;
	vec2 g = abs(fract(vec2(lon, lat) / radians(10.0) + 0.5) - 0.5) / fwidth(vec2(lon, lat) / radians(10.0));
	float line = 1.0 - smoothstep(0.5, 1.5, min(g.x, g.y));
	col = mix(col, grid_color.rgb, line * grid_lines);
	ALBEDO = col * brightness;
	ROUGHNESS = mix(0.9, 1.0 - ocean_gloss, ocean);
	float lights = texture(city_lights, uv).r;
	EMISSION = light_color * lights * lights_strength * 0.35;
}
