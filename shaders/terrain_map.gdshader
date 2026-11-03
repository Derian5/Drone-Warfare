shader_type spatial;
render_mode diffuse_lambert, specular_disabled;

// Topographic map look driven by painted layers in textures/map/:
//   height.png  - elevation (white = height_scale)
//   water.png   - rivers and lakes (white = water)
//   roads.png   - roads (white = road centre; soft edge becomes the casing)
//   towns.png   - settlement areas (white = built-up)
//   forest.png  - greener patches
// Contours, hillshade and the coordinate grid are computed here; tune them below.

group_uniforms Layers;
uniform sampler2D height_map : filter_linear, repeat_disable;
uniform sampler2D water_mask : filter_linear, repeat_disable, hint_default_black;
uniform sampler2D road_mask : filter_linear, repeat_disable, hint_default_black;
uniform sampler2D town_mask : filter_linear, repeat_disable, hint_default_black;
uniform sampler2D forest_mask : filter_linear, repeat_disable, hint_default_black;

group_uniforms Elevation_colors;
uniform vec3 lowland_color : source_color = vec3(0.85, 0.82, 0.63);
uniform vec3 midland_color : source_color = vec3(0.77, 0.75, 0.55);
uniform vec3 highland_color : source_color = vec3(0.64, 0.65, 0.46);
uniform vec3 forest_color : source_color = vec3(0.63, 0.66, 0.42);
uniform float forest_strength : hint_range(0.0, 1.0) = 0.35;
uniform vec2 midland_range = vec2(0.4, 1.8);
uniform vec2 highland_range = vec2(1.8, 3.8);
uniform float albedo_gain : hint_range(0.3, 1.5) = 0.86;

group_uniforms Hillshade;
uniform float relief_exaggeration = 4.0;
uniform vec3 light_direction = vec3(-0.7, 0.9, -0.6);
uniform vec3 shadow_tint : source_color = vec3(0.78, 0.84, 0.70);
uniform float shade_min : hint_range(0.0, 1.0) = 0.66;
uniform float shade_max : hint_range(0.5, 1.5) = 1.08;

group_uniforms Contours;
uniform float contour_interval = 0.25;
uniform int index_every = 4;
uniform vec4 contour_color : source_color = vec4(0.50, 0.46, 0.28, 0.38);
uniform vec4 index_contour_color : source_color = vec4(0.45, 0.40, 0.24, 0.45);
uniform float contour_px = 0.8;
uniform float index_contour_px = 1.3;

group_uniforms Roads_water_towns;
uniform vec3 road_color : source_color = vec3(0.88, 0.62, 0.30);
uniform vec3 road_casing_color : source_color = vec3(0.66, 0.42, 0.20);
uniform float road_fill_threshold : hint_range(0.0, 1.0) = 0.6;
uniform float road_casing_threshold : hint_range(0.0, 1.0) = 0.22;
uniform vec3 water_color : source_color = vec3(0.20, 0.40, 0.68);
uniform vec3 town_color : source_color = vec3(0.42, 0.38, 0.32);
uniform float town_block_scale = 1.3;

group_uniforms Grid;
uniform float grid_spacing = 10.0;
uniform vec4 grid_color : source_color = vec4(0.22, 0.23, 0.19, 0.38);
uniform float grid_px = 1.0;
uniform vec2 play_area_size = vec2(100.0, 68.0);
uniform float outside_darken : hint_range(0.0, 1.0) = 0.25;

group_uniforms Captured_zone;
// The previous region drawn inside this one (x, y, width, height in map units). Width 0 = none.
uniform vec4 captured_rect = vec4(0.0);
uniform vec4 captured_tint : source_color = vec4(0.22, 0.52, 0.95, 0.16);
uniform vec4 captured_border : source_color = vec4(0.16, 0.42, 0.9, 0.95);
uniform float captured_border_px = 2.5;
uniform float captured_dash = 2.0;

group_uniforms Internal;
uniform float height_scale = 6.0;
uniform vec2 texel = vec2(0.003);
uniform float world_step = 0.4;
uniform vec2 world_origin = vec2(-44.0, -40.0);
uniform vec2 world_size = vec2(188.0, 148.0);

varying vec3 map_position;

float hash21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise2(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x), mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0)), f.x), f.y);
}
// Periodic hairline where v is an integer, constant width in pixels.
float hair(float v, float px) {
	float d = abs(fract(v + 0.5) - 0.5);
	float w = d / max(fwidth(v), 0.0001);
	return 1.0 - smoothstep(px * 0.5, px * 0.5 + 1.0, w);
}

void vertex() {
	map_position = VERTEX;
}

void fragment() {
	vec2 p = map_position.xz;
	vec2 uv = (p - world_origin) / world_size;
	float h = texture(height_map, uv).r * height_scale;
	float hx = (texture(height_map, uv + vec2(texel.x, 0.0)).r - texture(height_map, uv - vec2(texel.x, 0.0)).r) * height_scale;
	float hz = (texture(height_map, uv + vec2(0.0, texel.y)).r - texture(height_map, uv - vec2(0.0, texel.y)).r) * height_scale;
	vec3 n = normalize(vec3(-hx / (2.0 * world_step) * relief_exaggeration, 1.0, -hz / (2.0 * world_step) * relief_exaggeration));
	float lit = clamp(dot(n, normalize(light_direction)) * 0.5 + 0.5, 0.0, 1.0);

	vec3 color = mix(lowland_color, midland_color, smoothstep(midland_range.x, midland_range.y, h));
	color = mix(color, highland_color, smoothstep(highland_range.x, highland_range.y, h));
	color = mix(color, forest_color, texture(forest_mask, uv).r * forest_strength);
	color *= 0.97 + 0.05 * noise2(p * 3.1);
	color = mix(color * shadow_tint, color, smoothstep(0.35, 0.75, lit));
	color *= mix(shade_min, shade_max, lit);

	float c = h / contour_interval;
	color = mix(color, contour_color.rgb, hair(c, contour_px) * contour_color.a);
	color = mix(color, index_contour_color.rgb, hair(c / float(max(index_every, 1)), index_contour_px) * index_contour_color.a);

	float road = texture(road_mask, uv).r;
	color = mix(color, road_casing_color, smoothstep(road_casing_threshold - 0.08, road_casing_threshold + 0.08, road) * 0.8);
	color = mix(color, road_color, smoothstep(road_fill_threshold - 0.1, road_fill_threshold + 0.1, road));

	color = mix(color, water_color, texture(water_mask, uv).r * 0.95);

	float town = texture(town_mask, uv).r;
	vec2 cell = abs(fract(p * town_block_scale) - 0.5);
	float blocks = step(cell.x, 0.27) * step(cell.y, 0.21) * step(0.3, hash21(floor(p * town_block_scale)));
	color = mix(color, town_color, town * blocks * 0.8);

	if (captured_rect.z > 0.0) {
		vec2 q = (p - captured_rect.xy) / captured_rect.zw;
		float inside = step(0.0, q.x) * step(q.x, 1.0) * step(0.0, q.y) * step(q.y, 1.0);
		color = mix(color, captured_tint.rgb, inside * captured_tint.a);
		float edge = min(min(q.x, 1.0 - q.x) * captured_rect.z, min(q.y, 1.0 - q.y) * captured_rect.w);
		float edge_px = edge / max(fwidth(p.x), 0.0001);
		float dash = step(0.35, fract((p.x + p.y) / captured_dash));
		color = mix(color, captured_border.rgb, inside * (1.0 - smoothstep(captured_border_px, captured_border_px + 1.0, edge_px)) * dash * captured_border.a);
	}

	float grid = max(hair(p.x / grid_spacing, grid_px), hair(p.y / grid_spacing, grid_px));
	color = mix(color, grid_color.rgb, grid * grid_color.a);

	float outside = max(max(-p.x, p.x - play_area_size.x), max(-p.y, p.y - play_area_size.y));
	color *= 1.0 - smoothstep(0.0, 18.0, outside) * outside_darken;

	NORMAL = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	ALBEDO = clamp(color, 0.0, 1.0) * albedo_gain;
	ROUGHNESS = 1.0;
}
