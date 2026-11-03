extends Control
## Model viewer for checking imported assets (default: res://models/Rocket.blend).
## Open tools/model_viewer.tscn in the Godot editor and press F6.
##
## Two views:
##   STUDIO  - neutral backdrop, orbit camera (drag = rotate, wheel = zoom, right drag = pan).
##   IN GAME - the real battlefield terrain, lighting and camera; the model flies a route.
## Panel: every animation from every AnimationPlayer, speed/loop controls, materials,
## mesh stats, scale and forward-axis settings for in-game flight.

const Simulation = preload("res://scripts/sim/simulation.gd")
const BattlefieldScene = preload("res://scenes/regions/01_valley.tscn")

@export_file("*.blend", "*.glb", "*.gltf", "*.fbx", "*.tscn", "*.scn") var model_path := "res://models/Rocket.blend"

const AXES = {"-Z (Godot forward)": Vector3(0, 0, -1), "+Z": Vector3(0, 0, 1), "+X": Vector3(1, 0, 0), "-X": Vector3(-1, 0, 0), "+Y (nose up)": Vector3(0, 1, 0), "-Y": Vector3(0, -1, 0)}
const ROUTE = [Vector2(15, 45), Vector2(30, 52), Vector2(52, 50), Vector2(70, 40), Vector2(82, 26), Vector2(82, 14)]

var source: PackedScene
var studio_view: SubViewportContainer
var studio_viewport: SubViewport
var studio_root: Node3D
var studio_camera: Camera3D
var studio_model: Node3D
var game_view: SubViewportContainer
var game_world: Battlefield
var game_model: Node3D
var game_pivot: Node3D
var players: Array = []          # [{player, model}] for both copies
var current_animation = ""
var info: RichTextLabel
var anim_box: VBoxContainer
var status: Label
var speed = 1.0
var loop = true
var paused = false
var mode = "studio"
var yaw = 0.6
var pitch = 0.45
var distance = 6.0
var focus = Vector3.ZERO
var model_radius = 1.0
var game_scale = 1.0
var game_size = 6.0
var forward_axis = Vector3(0, 0, -1)
var fly = true
var fly_t = 0.0
var route_length = 0.0
var dragging = 0
var file_lights: Array = []
var axis_pick: OptionButton
var model_pick: OptionButton
var use_file_lights = false
var fire_material: ShaderMaterial
var fire_meshes: Array = []

const FIRE_SHADER = """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
uniform float height = 1.07;
uniform float intensity = 1.0;
varying float along;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1)), f.x), f.y);
}
void vertex() {
	along = clamp(VERTEX.y / height, 0.0, 1.0);
	float flicker = 1.0 + 0.12 * sin(TIME * 23.0) + 0.08 * sin(TIME * 37.0 + VERTEX.x * 9.0);
	VERTEX.xz *= mix(1.0, 0.75 + 0.25 * flicker, along);
	VERTEX.y *= flicker;
}
void fragment() {
	float n = noise(vec2(UV.x * 6.0, UV.y * 4.0 - TIME * 9.0)) * 0.6 + noise(vec2(UV.x * 13.0, UV.y * 9.0 - TIME * 15.0)) * 0.4;
	float a = (1.0 - along) * (0.55 + 0.45 * n);
	vec3 hot = vec3(1.0, 0.95, 0.75);
	vec3 mid = vec3(1.0, 0.55, 0.15);
	vec3 cool = vec3(0.7, 0.15, 0.05);
	vec3 c = mix(hot, mid, smoothstep(0.0, 0.35, along));
	c = mix(c, cool, smoothstep(0.35, 0.9, along));
	float facing = pow(abs(dot(normalize(NORMAL), normalize(VIEW))), 1.5);
	ALBEDO = c * a * facing * intensity * 1.1;
}
"""

## Strip things that should not be part of a game asset, and replace the Blender fire
## volume (volumetric shaders do not survive glTF export) with an animated Godot flame.
func _prepare(root: Node3D) -> Node3D:
	for camera in root.find_children("*", "Camera3D", true, false):
		camera.get_parent().remove_child(camera)
		camera.queue_free()
	for light in root.find_children("*", "Light3D", true, false):
		light.visible = use_file_lights
		file_lights.append(light)
	if fire_material == null:
		var shader = Shader.new()
		shader.code = FIRE_SHADER
		fire_material = ShaderMaterial.new()
		fire_material.shader = shader
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_node: MeshInstance3D = node
		if mesh_node.mesh == null or not ("fire" in mesh_node.name.to_lower() or "flame" in mesh_node.name.to_lower()):
			continue
		var box = mesh_node.mesh.get_aabb()
		fire_material.set_shader_parameter("height", maxf(0.001, box.end.y))
		mesh_node.material_override = fire_material
		mesh_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		fire_meshes.append(mesh_node)
	return root

func _ready() -> void:
	_build_ui()
	var files = _model_files()
	# Default to the newest model in res://models unless model_path was set explicitly.
	if not files.is_empty() and model_path == "res://models/Rocket.blend":
		model_path = files[0]
	for path in files:
		model_pick.add_item(path.trim_prefix("res://models/"))
		model_pick.set_item_metadata(model_pick.item_count - 1, path)
		if path == model_path:
			model_pick.select(model_pick.item_count - 1)
	_load_model(model_path)

func _model_files() -> Array:
	var found = []
	_scan("res://models", found)
	found.sort_custom(func(a, b): return FileAccess.get_modified_time(a) > FileAccess.get_modified_time(b))
	return found

func _scan(path: String, found: Array) -> void:
	var dir = DirAccess.open(path)
	if dir == null:
		return
	for name in dir.get_files():
		if name.get_extension().to_lower() in ["blend", "glb", "gltf", "fbx"]:
			found.append(path.path_join(name))
	for sub in dir.get_directories():
		_scan(path.path_join(sub), found)

func _unload() -> void:
	for node in [studio_model, game_pivot]:
		if is_instance_valid(node):
			node.get_parent().remove_child(node)
			node.queue_free()
	studio_model = null
	game_model = null
	game_pivot = null
	players.clear()
	fire_meshes.clear()
	file_lights.clear()
	current_animation = ""

func _load_model(path: String) -> void:
	_unload()
	model_path = path
	get_window().title = "Model viewer — " + model_path
	status.text = model_path
	if not ResourceLoader.exists(model_path):
		status.text = "Cannot find %s." % model_path
		return
	source = load(model_path) as PackedScene
	if source == null:
		status.text = "%s did not import as a scene. For .blend files set Editor Settings > FileSystem > Import > Blender path." % model_path
		return
	studio_model = _prepare(source.instantiate())
	studio_root.add_child(studio_model)
	var box = _aabb(studio_model)
	model_radius = maxf(0.001, box.size.length() * 0.5)
	focus = box.get_center()
	distance = model_radius * 4.2
	game_scale = game_size / maxf(box.size.x, maxf(box.size.y, box.size.z))
	if box.size.y >= box.size.x and box.size.y >= box.size.z:
		forward_axis = Vector3.UP
		axis_pick.select(AXES.keys().find("+Y (nose up)"))
	_build_game_copy()
	_collect_players()
	_fill_animations()
	_fill_info(box)
	_update_camera()
	_set_mode(mode)
	if not current_animation.is_empty():
		_play(current_animation)

# ---------------------------------------------------------------- UI

func _build_ui() -> void:
	var background = ColorRect.new()
	background.color = Color("12171e")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var row = HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(row)
	var stage = Control.new()
	stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(stage)
	studio_view = SubViewportContainer.new()
	studio_view.stretch = true
	studio_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	studio_view.gui_input.connect(_studio_input)
	stage.add_child(studio_view)
	studio_viewport = SubViewport.new()
	studio_viewport.own_world_3d = true
	studio_viewport.msaa_3d = Viewport.MSAA_4X
	studio_view.add_child(studio_viewport)
	studio_root = Node3D.new()
	studio_viewport.add_child(studio_root)
	_build_studio()
	game_view = SubViewportContainer.new()
	game_view.stretch = true
	game_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	game_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(game_view)
	var game_viewport = SubViewport.new()
	game_viewport.msaa_3d = Viewport.MSAA_2X
	game_view.add_child(game_viewport)
	game_world = BattlefieldScene.instantiate()
	game_viewport.add_child(game_world)
	var sim = Simulation.new(load("res://data/balance.tres"), load("res://data/campaign.tres"))
	sim.start_region(0, game_world.layout())
	game_world.setup(sim)
	game_viewport.size_changed.connect(func(): game_world.set_view(Vector2(game_viewport.size), 1.0))
	var panel = PanelContainer.new()
	panel.custom_minimum_size.x = 320
	var style = StyleBoxFlat.new()
	style.bg_color = Color("1a2029")
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", style)
	row.add_child(panel)
	var scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var column = VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 6)
	scroll.add_child(column)
	_title("MODEL VIEWER", column, 18)
	model_pick = OptionButton.new()
	model_pick.tooltip_text = "Models found in res://models (newest first)"
	model_pick.item_selected.connect(func(i): _load_model(str(model_pick.get_item_metadata(i))))
	column.add_child(model_pick)
	status = _text(model_path, column, Color("8995a0"))
	var modes = HBoxContainer.new()
	column.add_child(modes)
	_button("STUDIO", modes, func(): _set_mode("studio"))
	_button("IN GAME", modes, func(): _set_mode("game"))
	_title("ANIMATIONS", column)
	anim_box = VBoxContainer.new()
	column.add_child(anim_box)
	var controls = HBoxContainer.new()
	column.add_child(controls)
	var pause_button = _button("Pause", controls, func(): pass)
	pause_button.pressed.connect(func():
		paused = not paused
		pause_button.text = "Resume" if paused else "Pause"
		for entry in players:
			if paused:
				entry.player.pause()
			elif not current_animation.is_empty():
				entry.player.play()
	)
	_button("Stop / rest pose", controls, func():
		for entry in players:
			entry.player.stop()
			if entry.player.has_animation("RESET"):
				entry.player.play("RESET")
				entry.player.seek(0, true)
				entry.player.stop(true)
		current_animation = ""
	)
	var loop_box = CheckBox.new()
	loop_box.text = "Loop"
	loop_box.button_pressed = true
	loop_box.toggled.connect(func(on):
		loop = on
		if not current_animation.is_empty():
			_play(current_animation)
	)
	column.add_child(loop_box)
	_slider(column, "Speed", 0.1, 3.0, 1.0, func(v):
		speed = v
		for entry in players:
			entry.player.speed_scale = v
	)
	_title("IN GAME", column)
	_slider(column, "Size on map (units)", 0.5, 12.0, game_size, func(v):
		game_size = v
		_apply_game_scale()
	)
	var axis_row = HBoxContainer.new()
	column.add_child(axis_row)
	_text("Model nose points", axis_row, Color("e9edf0"))
	axis_pick = OptionButton.new()
	for key in AXES:
		axis_pick.add_item(key)
	axis_pick.item_selected.connect(func(i):
		forward_axis = AXES[axis_pick.get_item_text(i)]
	)
	axis_row.add_child(axis_pick)
	var fly_box = CheckBox.new()
	fly_box.text = "Fly along a route (otherwise hover over the base)"
	fly_box.button_pressed = true
	fly_box.toggled.connect(func(on): fly = on)
	column.add_child(fly_box)
	_title("FILE OPTIONS", column)
	var lights_box = CheckBox.new()
	lights_box.text = "Use lights from the .blend file"
	lights_box.toggled.connect(func(on):
		use_file_lights = on
		for light in file_lights:
			if is_instance_valid(light):
				light.visible = on
	)
	column.add_child(lights_box)
	var fire_box = CheckBox.new()
	fire_box.text = "Animated Godot flame on the fire mesh"
	fire_box.button_pressed = true
	fire_box.toggled.connect(func(on):
		for mesh_node in fire_meshes:
			if is_instance_valid(mesh_node):
				mesh_node.material_override = fire_material if on else null
	)
	column.add_child(fire_box)
	_title("DETAILS", column)
	info = RichTextLabel.new()
	info.fit_content = true
	info.bbcode_enabled = true
	info.selection_enabled = true
	info.add_theme_font_size_override("normal_font_size", 12)
	info.add_theme_font_size_override("bold_font_size", 12)
	column.add_child(info)
	_text("Studio: drag = rotate · right drag = pan · wheel = zoom", column, Color("8995a0"))

func _title(text: String, parent: Node, size: int = 13) -> Label:
	var node = Label.new()
	node.text = text
	node.add_theme_font_size_override("font_size", size)
	node.add_theme_color_override("font_color", Color("1fbecb"))
	parent.add_child(node)
	return node

func _text(text: String, parent: Node, color: Color) -> Label:
	var node = Label.new()
	node.text = text
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	node.add_theme_font_size_override("font_size", 12)
	node.add_theme_color_override("font_color", color)
	parent.add_child(node)
	return node

func _button(text: String, parent: Node, action: Callable) -> Button:
	var node = Button.new()
	node.text = text
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	node.pressed.connect(action)
	parent.add_child(node)
	return node

func _slider(parent: Node, caption: String, low: float, high: float, value: float, changed: Callable) -> void:
	var row = HBoxContainer.new()
	parent.add_child(row)
	var label = _text(caption, row, Color("e9edf0"))
	var number = Label.new()
	number.custom_minimum_size.x = 40
	number.text = "%.2f" % value
	row.add_child(number)
	var slider = HSlider.new()
	slider.min_value = low
	slider.max_value = high
	slider.step = 0.05
	slider.value = value
	slider.custom_minimum_size.x = 120
	slider.value_changed.connect(func(v):
		number.text = "%.2f" % v
		changed.call(v)
	)
	row.add_child(slider)

# ---------------------------------------------------------------- studio

func _build_studio() -> void:
	var env_node = WorldEnvironment.new()
	var env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("cfcfcb")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	env.ambient_light_energy = 0.35
	env_node.environment = env
	studio_root.add_child(env_node)
	var key = DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-50, -140, 0)
	key.light_energy = 0.9
	key.shadow_enabled = true
	studio_root.add_child(key)
	var fill = DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20, 60, 0)
	fill.light_energy = 0.3
	studio_root.add_child(fill)
	studio_camera = Camera3D.new()
	studio_camera.fov = 35
	studio_root.add_child(studio_camera)
	studio_camera.current = true

func _studio_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			distance = maxf(model_radius * 0.3, distance * 0.9)
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			distance = minf(model_radius * 30, distance * 1.1)
		elif event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
			dragging = event.button_index if event.pressed else 0
	elif event is InputEventMouseMotion and dragging != 0:
		if dragging == MOUSE_BUTTON_LEFT:
			yaw -= event.relative.x * 0.01
			pitch = clampf(pitch + event.relative.y * 0.01, -1.4, 1.4)
		else:
			var basis = studio_camera.global_transform.basis
			focus += (-basis.x * event.relative.x + basis.y * event.relative.y) * distance * 0.002
	_update_camera()

func _update_camera() -> void:
	if studio_camera == null:
		return
	var offset = Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * distance
	studio_camera.near = maxf(0.001, distance * 0.01)
	studio_camera.far = distance * 50
	studio_camera.transform = Transform3D(Basis.looking_at(-offset, Vector3.UP), focus + offset)

# ---------------------------------------------------------------- in game

func _build_game_copy() -> void:
	game_pivot = Node3D.new()
	game_world.drone_layer.add_child(game_pivot)
	game_model = _prepare(source.instantiate())
	game_pivot.add_child(game_model)
	var box = _aabb(game_model)
	game_model.position = -box.get_center()
	route_length = 0.0
	for i in range(ROUTE.size() - 1):
		route_length += ROUTE[i].distance_to(ROUTE[i + 1])
	_apply_game_scale()
	game_world.show_draft(ROUTE)

func _apply_game_scale() -> void:
	if game_model == null:
		return
	var box = _aabb_local(game_model)
	game_scale = game_size / maxf(0.001, maxf(box.size.x, maxf(box.size.y, box.size.z)))
	game_pivot.scale = Vector3.ONE * game_scale

func _route_point(distance_along: float) -> Array:
	var walked = 0.0
	for i in range(ROUTE.size() - 1):
		var a: Vector2 = ROUTE[i]
		var b: Vector2 = ROUTE[i + 1]
		var seg = a.distance_to(b)
		if walked + seg >= distance_along:
			return [a.lerp(b, (distance_along - walked) / seg), (b - a).normalized()]
		walked += seg
	return [ROUTE.back(), (ROUTE[ROUTE.size() - 1] - ROUTE[ROUTE.size() - 2]).normalized()]

func _process(delta: float) -> void:
	if game_pivot == null:
		return
	game_world.sync(delta)
	var where: Vector2 = Vector2(15, 45)
	var heading = Vector2(0, -1)
	if fly:
		fly_t = fmod(fly_t + delta * 16.0, route_length)
		var sample = _route_point(fly_t)
		where = sample[0]
		heading = sample[1]
	var altitude = game_world.flight_altitude + game_size * 0.5
	game_pivot.position = Vector3(where.x, game_world.terrain_height(where) + altitude, where.y)
	# Rotate so the model's nose axis points along the flight direction.
	var travel = Vector3(heading.x, 0, heading.y).normalized()
	var nose = forward_axis
	var align = Basis.IDENTITY
	if nose.dot(Vector3.UP) > 0.9 or nose.dot(Vector3.DOWN) > 0.9:
		align = Basis(Vector3.RIGHT, -PI / 2 * signf(nose.y))
		nose = Vector3(0, 0, -1)
	var yaw_angle = atan2(-travel.x, -travel.z) - atan2(-nose.x, -nose.z)
	game_pivot.basis = (Basis(Vector3.UP, yaw_angle) * align).scaled(Vector3.ONE * game_scale)

func _set_mode(value: String) -> void:
	mode = value
	studio_view.visible = mode == "studio"
	game_view.visible = mode == "game"

# ---------------------------------------------------------------- animations & info

func _collect_players() -> void:
	players.clear()
	for root in [studio_model, game_model]:
		for player in root.find_children("*", "AnimationPlayer", true, false):
			players.append({"player": player, "root": root})

func _fill_animations() -> void:
	for child in anim_box.get_children():
		child.queue_free()
	var names = []
	for entry in players:
		if entry.root != studio_model:
			continue
		for anim in entry.player.get_animation_list():
			if anim != "RESET" and not names.has(anim):
				names.append(anim)
	if names.is_empty():
		_text("No animations found in this model.", anim_box, Color("f2a71b"))
		return
	for anim in names:
		var length = 0.0
		for entry in players:
			if entry.player.has_animation(anim):
				length = entry.player.get_animation(anim).length
				break
		_button("%s  (%.2fs)" % [anim, length], anim_box, func(): _play(anim))
	current_animation = names[0]

func _play(anim: String) -> void:
	current_animation = anim
	paused = false
	for entry in players:
		var player: AnimationPlayer = entry.player
		if not player.has_animation(anim):
			continue
		player.get_animation(anim).loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
		player.speed_scale = speed
		player.stop()
		player.play(anim)
	status.text = "Playing: %s" % anim

func _fill_info(box: AABB) -> void:
	var meshes = studio_model.find_children("*", "MeshInstance3D", true, false)
	var vertices = 0
	var lines = []
	var materials = {}
	for node in meshes:
		var mesh_node: MeshInstance3D = node
		if mesh_node.mesh == null:
			continue
		for s in range(mesh_node.mesh.get_surface_count()):
			var arrays = mesh_node.mesh.surface_get_arrays(s)
			vertices += (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
			var material = mesh_node.get_active_material(s)
			var key = material.resource_name if material != null and not material.resource_name.is_empty() else ("<none>" if material == null else str(material))
			if material == fire_material:
				key = "Godot flame shader (replaces the Blender fire volume)"
			if not materials.has(key):
				materials[key] = _describe_material(material)
	lines.append("[b]Size[/b]: %.2f × %.2f × %.2f m" % [box.size.x, box.size.y, box.size.z])
	lines.append("[b]Meshes[/b]: %d · vertices: %d" % [meshes.size(), vertices])
	lines.append("[b]Skeletons[/b]: %d · AnimationPlayers: %d" % [studio_model.find_children("*", "Skeleton3D", true, false).size(), players.size() / 2])
	if players.is_empty():
		lines.append("[color=#f2a71b]No exported animations. Blender volume/simulation/shader-driven effects are not carried by glTF; only object, bone and shape-key actions are.[/color]")
	if not fire_meshes.is_empty():
		lines.append("[color=#1fbecb]Fire mesh replaced by an animated Godot flame shader (toggle in FILE OPTIONS).[/color]")
	lines.append("")
	lines.append("[b]Materials (%d)[/b]" % materials.size())
	for key in materials:
		lines.append("• [b]%s[/b] — %s" % [key, materials[key]])
	lines.append("")
	lines.append("[b]Node tree[/b]")
	_tree(studio_model, 0, lines)
	info.text = "\n".join(lines)

func _describe_material(material: Material) -> String:
	if material == null:
		return "no material (renders default white)"
	if material == fire_material:
		return "animated, additive, no shadows"
	if material is StandardMaterial3D or material is ORMMaterial3D:
		var m: BaseMaterial3D = material
		var parts = ["albedo #%s" % m.albedo_color.to_html(false)]
		if m.albedo_texture != null:
			parts.append("[color=#3cc46a]albedo texture[/color] %s" % m.albedo_texture.resource_path.get_file())
		else:
			parts.append("[color=#f2a71b]no albedo texture[/color]")
		if m.roughness_texture != null:
			parts.append("roughness texture")
		if m.normal_enabled and m.normal_texture != null:
			parts.append("normal map")
		parts.append("metallic %.2f, roughness %.2f" % [m.metallic, m.roughness])
		if m.emission_enabled:
			parts.append("emission #%s ×%.1f" % [m.emission.to_html(false), m.emission_energy_multiplier])
		if m.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
			parts.append("transparent")
		return ", ".join(parts)
	return material.get_class()

func _tree(node: Node, depth: int, lines: Array) -> void:
	if depth > 6 or lines.size() > 80:
		return
	lines.append("%s%s [color=#8995a0](%s)[/color]" % ["   ".repeat(depth), node.name, node.get_class()])
	for child in node.get_children():
		_tree(child, depth + 1, lines)

func _aabb(root: Node3D) -> AABB:
	var result = AABB()
	var first = true
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var visual: MeshInstance3D = node
		if visual.mesh == null:
			continue
		var box = visual.global_transform * visual.get_aabb() if visual.is_inside_tree() else visual.get_aabb()
		if first:
			result = box
			first = false
		else:
			result = result.merge(box)
	return result if not first else AABB(Vector3(-0.5, -0.5, -0.5), Vector3.ONE)

func _aabb_local(root: Node3D) -> AABB:
	# Bounds relative to the model root, independent of where it currently is.
	var inverse = root.global_transform.affine_inverse() if root.is_inside_tree() else Transform3D.IDENTITY
	var result = AABB()
	var first = true
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var visual: MeshInstance3D = node
		if visual.mesh == null:
			continue
		var box = inverse * (visual.global_transform * visual.get_aabb())
		if first:
			result = box
			first = false
		else:
			result = result.merge(box)
	return result if not first else AABB(Vector3(-0.5, -0.5, -0.5), Vector3.ONE)
