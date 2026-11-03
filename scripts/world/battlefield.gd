class_name Battlefield
extends Node3D
## Root of every region scene (scenes/regions/*.tscn). Everything visible is a node in the
## scene: terrain, sites (move them to change the map), labels, camera and light.
## This script syncs the simulation onto those nodes and spawns drones and effects.

@export_group("Scenes")
@export var free_drone_scene: PackedScene
@export var modular_drone_scene: PackedScene
@export var hunter_scene: PackedScene
@export var explosion_scene: PackedScene
@export var small_explosion_scene: PackedScene
@export var flak_scene: PackedScene
@export var tracer_scene: PackedScene
## Burst fired from the base when the player clicks/taps a hunter.
@export var tap_shot_scene: PackedScene = preload("res://fx/tap_shot.tscn")
@export var muzzle_flash_scene: PackedScene = preload("res://fx/muzzle_flash.tscn")
@export var tap_burst_rounds := 3
@export var missile_scene: PackedScene
@export var smoke_scene: PackedScene
@export var launch_dust_scene: PackedScene
@export var booster_trail_scene: PackedScene
@export var deploy_scene: PackedScene
@export var drone_shadow_texture: Texture2D

@export_group("Flight")
@export var flight_altitude := 3.4
@export var free_drone_scale := 1.6
@export var modular_drone_scale := 1.45
@export var hunter_scale := 1.5
@export var shadow_size := 0.07
@export var show_shadows := true
@export var missile_trail_puffs := 4

@export_group("Routes")
@export var route_width := 0.3
@export var selected_route_width := 0.42
@export var dash_length := 1.25
@export var dash_gap := 0.85
@export var arrow_head_size := 1.6
@export var draft_color := Color.WHITE
@export var route_lift := 0.22
## Translucent strip under route segments that pass through air-defense zones.
@export var danger_color := Color(0.85, 0.12, 0.1, 0.35)
@export var danger_width := 1.3

@export_group("Rings")
@export var gun_ring_color := Color(0.76, 0.16, 0.18, 0.75)
@export var missile_ring_color := Color(0.9, 0.45, 0.1, 0.8)
@export var jammer_ring_color := Color(0.55, 0.3, 0.85, 0.8)
@export var base_defense_ring_color := Color(0.25, 0.5, 0.9, 0.6)
@export var ring_width := 0.22
@export var selection_ring_color := Color(0.12, 0.73, 0.77, 0.95)
@export var selection_ring_width := 0.35
@export var selection_ring_radius := 7.5

@export_group("Orbit (planet regions)")
## Drag on empty space rotates the globe (the camera orbits it, the sun follows).
@export var orbit_camera := false
## Radians per dragged pixel.
@export var orbit_drag_speed := 0.006
@export var orbit_pitch_limit := 65.0
## Slow turn of the globe when the player does not touch it.
@export var orbit_idle_spin := 0.04
@export var orbit_idle_delay := 8.0
@export var min_zoom := 0.45
@export var max_zoom := 1.3

@export_group("Camera")
## Map width visible at zoom 1 (world units). Depth is derived from the viewport aspect.
@export var view_width := 103.0
@export var view_depth := 70.0
@export var victory_zoom := 1.32

@onready var camera: Camera3D = $Camera
@onready var terrain: Node3D = $Terrain
@onready var sites_root: Node3D = $Sites
@onready var route_layer: Node3D = $Layers/Routes
@onready var draft_layer: Node3D = $Layers/Draft
@onready var drone_layer: Node3D = $Layers/Drones
@onready var fx_layer: Node3D = $Layers/Fx

var sim: RefCounted
var balance: GameBalance
var view_scale := 1.0
var zoom := 1.0
var zoom_target := 1.0
var base_width := 103.0
var selected_route := -1
## Route under a dragged line (drawn like a selected one).
var hover_route := -1
var selected_target := ""
var floaters: Array = []
var _drones: Dictionary = {}
var _hunters: Dictionary = {}
var _rings: Array = []
var _ring_signature := ""
var _selection_ring: MeshInstance3D
var _time := 0.0
var _materials := {}

# ---------------------------------------------------------------- layout

func sites() -> Array:
	return sites_root.get_children().filter(func(n): return n is MapSite)

func site_for(id: String) -> MapSite:
	for site in sites():
		if (id == "base" and site.is_player_base) or (site.data != null and site.data.id == id) or (site.is_build_pad and site.build_id == id):
			return site
	return null

## Layout handed to the simulation, read from the scene.
func layout() -> Dictionary:
	var result = {"base": Vector2(15, 45), "targets": [], "build_sites": []}
	for site in sites():
		if site.is_player_base:
			result.base = site.map_position()
		elif site.is_build_pad:
			result.build_sites.append({"id": site.build_id, "position": site.map_position(), "price": site.build_price})
		elif site.data != null:
			result.targets.append({"position": site.map_position(), "data": site.data, "reserve": site.is_reserve})
	var waypoint = sites_root.get_node_or_null("FreeRouteWaypoint") as Node3D
	if waypoint != null:
		result.waypoint = Vector2(waypoint.global_position.x, waypoint.global_position.z) if not terrain is PlanetTerrain else waypoint.get_meta("map_coords", result.base)
	if terrain is MapTerrain:
		result.height = terrain_height
	return result

func setup(state: RefCounted) -> void:
	sim = state
	balance = sim.balance
	for site in sites():
		var p = site.map_position()
		site.global_position = to_world(p)
		if terrain is PlanetTerrain:
			var up = terrain.up_at(p)
			site.global_basis = Basis.looking_at(-camera.global_basis.z.slide(up).normalized() if absf(camera.global_basis.z.dot(up)) < 0.99 else Vector3.FORWARD, up) * Basis.from_scale(site.scale)
	if _selection_ring == null:
		_selection_ring = _ring_mesh(selection_ring_radius, selection_ring_color, selection_ring_width)
	_selection_ring.visible = false
	if not sim.effect.is_connected(_effect):
		sim.effect.connect(_effect)
		sim.floater.connect(_floater)
		sim.shot.connect(_shot)
	_clear_units()
	_ring_signature = ""
	refresh_routes()

func _clear_units() -> void:
	for entry in _drones.values():
		entry.node.queue_free()
		if entry.shadow:
			entry.shadow.queue_free()
	_drones.clear()
	for node in _hunters.values():
		node.queue_free()
	_hunters.clear()

func terrain_height(p: Vector2) -> float:
	return terrain.height_at(p) if terrain != null else 0.0

func to_world(p: Vector2, lift: float = 0.0) -> Vector3:
	return terrain.to_world(p, lift)

func up_at(p: Vector2) -> Vector3:
	return terrain.up_at(p)

# ---------------------------------------------------------------- camera

func set_view(size: Vector2, scale: float) -> void:
	view_scale = scale
	if size.x > 0 and size.y > 0 and camera != null:
		var pitch = -camera.rotation.x
		base_width = maxf(view_width, view_depth * sin(pitch) * size.x / size.y) if camera.projection == Camera3D.PROJECTION_ORTHOGONAL else view_width
		_apply_zoom()

func _apply_zoom() -> void:
	if camera.projection == Camera3D.PROJECTION_ORTHOGONAL:
		camera.size = base_width * zoom
	else:
		if not camera.has_meta("base_fov"):
			camera.set_meta("base_fov", camera.fov)
		camera.fov = clampf(camera.get_meta("base_fov") * zoom, 5, 150)

var _orbit := {}

func _process(delta: float) -> void:
	if camera != null and not camera.has_meta("base_fov"):
		camera.set_meta("base_fov", camera.fov)
	if orbit_camera and camera != null and terrain != null:
		if _orbit.is_empty():
			var off = camera.global_position - terrain.global_position
			var sun = get_node_or_null("Sun") as Node3D
			_orbit = {"yaw": atan2(off.x, off.z), "pitch": asin(off.y / off.length()), "dist": off.length(), "idle": 0.0, "yaw0": atan2(off.x, off.z), "sun": sun.global_basis if sun else Basis.IDENTITY}
		_orbit.idle += delta
		if _orbit.idle > orbit_idle_delay:
			_orbit.yaw += orbit_idle_spin * delta
		_apply_orbit()
	if camera != null and absf(zoom - zoom_target) > 0.001:
		zoom = lerpf(zoom, zoom_target, minf(1.0, delta * 1.6))
		_apply_zoom()

func _apply_orbit() -> void:
	var y: float = _orbit.yaw
	var p: float = _orbit.pitch
	var center = terrain.global_position
	var pos = center + Vector3(cos(p) * sin(y), sin(p), cos(p) * cos(y)) * float(_orbit.dist)
	camera.look_at_from_position(pos, center, Vector3.UP)
	var sun = get_node_or_null("Sun") as Node3D
	if sun:
		sun.global_basis = Basis(Vector3.UP, y - float(_orbit.yaw0)) * _orbit.sun

## Rotates the globe by a screen drag (planet regions only).
func orbit_drag(relative: Vector2) -> void:
	if not orbit_camera or _orbit.is_empty():
		return
	_orbit.idle = 0.0
	_orbit.yaw -= relative.x * orbit_drag_speed * zoom
	_orbit.pitch = clampf(_orbit.pitch + relative.y * orbit_drag_speed * zoom, deg_to_rad(-orbit_pitch_limit), deg_to_rad(orbit_pitch_limit))
	_apply_orbit()

func orbit_touch() -> void:
	if not _orbit.is_empty():
		_orbit.idle = 0.0

## Mouse wheel / pinch zoom (planet regions only).
func zoom_by(factor: float) -> void:
	if not orbit_camera:
		return
	zoom_target = clampf(zoom_target * factor, min_zoom, max_zoom)
	orbit_touch()

## False for points on the far side of the globe (their labels are hidden).
func is_facing(p: Vector2) -> bool:
	if not (terrain is PlanetTerrain):
		return true
	var point = to_world(p)
	return (point - terrain.global_position).normalized().dot((camera.global_position - point).normalized()) > 0.05

func screen_to_map(screen: Vector2) -> Vector2:
	var s = screen * view_scale
	return terrain.pick(camera.project_ray_origin(s), camera.project_ray_normal(s))

func map_to_screen(point: Vector2, lift: float = 0.0) -> Vector2:
	return camera.unproject_position(to_world(point, lift)) / view_scale

func world_to_screen(point: Vector3) -> Vector2:
	return camera.unproject_position(point) / view_scale

func route_near(screen: Vector2, radius: float = 18.0) -> int:
	var nearest = -1
	var best = radius
	for path in sim.routes:
		for i in range(path.points.size() - 1):
			var a = map_to_screen(path.points[i])
			var b = map_to_screen(path.points[i + 1])
			var distance = screen.distance_to(Geometry2D.get_closest_point_to_segment(screen, a, b))
			if distance < best:
				best = distance
				nearest = int(path.id)
	return nearest

func target_near(screen: Vector2, radius: float = 46.0) -> String:
	var nearest = ""
	var best = radius
	for obj in sim.active_targets():
		var distance = screen.distance_to(map_to_screen(obj.position, 1.5))
		if distance < best:
			best = distance
			nearest = obj.id
	return nearest

func pad_near(screen: Vector2, radius: float = 40.0) -> String:
	for site in sim.layout.get("build_sites", []):
		if screen.distance_to(map_to_screen(site.position, 1.0)) < radius:
			return site.id
	return ""

func hunter_near(screen: Vector2, radius: float = 42.0) -> int:
	var best = radius
	var found = -1
	for hunter in sim.hunters:
		var d = screen.distance_to(world_to_screen(to_world(hunter.position, flight_altitude + 0.6)))
		if d < best:
			best = d
			found = int(hunter.id)
	return found

# ---------------------------------------------------------------- ground lines

func _flat(color: Color) -> StandardMaterial3D:
	if _materials.has(color):
		return _materials[color]
	var material = StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	if color.a < 1.0:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_materials[color] = material
	return material

func _strip(mesh: ImmediateMesh, a: Vector2, b: Vector2, width: float, lift: float) -> void:
	if a.distance_to(b) < 0.02:
		return
	var side = (b - a).normalized().orthogonal() * width * 0.5
	for p in [a - side, b - side, a + side, a + side, b - side, b + side]:
		mesh.surface_add_vertex(to_world(p, lift))

func _mesh_node(parent: Node3D, mesh: ImmediateMesh, color: Color) -> MeshInstance3D:
	var node = MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = _flat(color)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)
	return node

func _polyline(parent: Node3D, points: Array, color: Color, width: float, closed: bool = false, lift: float = 0.12) -> MeshInstance3D:
	var mesh = ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var count = points.size() if closed else points.size() - 1
	for i in range(count):
		var a: Vector2 = points[i]
		var b: Vector2 = points[(i + 1) % points.size()]
		var pieces = maxi(1, ceili(a.distance_to(b)))
		for k in range(pieces):
			_strip(mesh, a.lerp(b, float(k) / pieces), a.lerp(b, float(k + 1) / pieces), width, lift)
	mesh.surface_end()
	return _mesh_node(parent, mesh, color)

func _circle(center: Vector2, radius: float) -> Array:
	var points = []
	for i in range(96):
		points.append(center + Vector2.from_angle(TAU * i / 96.0) * radius)
	return points

## A ring that follows the ground at a fixed map position.
func _ground_ring(center: Vector2, radius: float, color: Color, width: float) -> MeshInstance3D:
	return _polyline(self, _circle(center, radius), color, width, true)

## A movable flat ring (selection marker).
func _ring_mesh(radius: float, color: Color, width: float) -> MeshInstance3D:
	var mesh = ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var points = _circle(Vector2.ZERO, radius)
	for i in range(points.size()):
		var a: Vector2 = points[i]
		var b: Vector2 = points[(i + 1) % points.size()]
		var side = (b - a).normalized().orthogonal() * width * 0.5
		for p in [a - side, b - side, a + side, a + side, b - side, b + side]:
			mesh.surface_add_vertex(Vector3(p.x, 0.3, p.y))
	mesh.surface_end()
	return _mesh_node(self, mesh, color)

func _dashed(parent: Node3D, points: Array, color: Color, width: float, arrow: bool) -> void:
	if points.size() < 2:
		return
	var mesh = ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var period = dash_length + dash_gap
	var offset = 0.0
	for i in range(points.size() - 1):
		var a: Vector2 = points[i]
		var b: Vector2 = points[i + 1]
		var length = a.distance_to(b)
		var t = 0.0
		while t < length - 0.0001:
			var phase = fmod(offset + t, period)
			var in_dash = phase < dash_length
			var end = minf(length, t + maxf((dash_length - phase) if in_dash else (period - phase), 0.02))
			if in_dash:
				_strip(mesh, a.lerp(b, t / length), a.lerp(b, end / length), width, route_lift)
			t = end
		offset += length
	if arrow:
		var tip: Vector2 = points.back()
		var previous: Vector2 = points[points.size() - 2]
		for k in range(points.size() - 2, -1, -1):
			if points[k].distance_to(tip) > 5.5:
				previous = points[k]
				break
		var direction = (tip - previous).normalized()
		var stop = tip - direction * 4.6
		var side = direction.orthogonal()
		_strip(mesh, stop - direction * arrow_head_size + side * arrow_head_size * 0.8, stop, width * 1.4, route_lift)
		_strip(mesh, stop - direction * arrow_head_size - side * arrow_head_size * 0.8, stop, width * 1.4, route_lift)
	mesh.surface_end()
	_mesh_node(parent, mesh, color)

func _clear(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()

func route_color(id: int) -> Color:
	return balance.route_color(id) if balance != null else Color.CYAN

## Parts of a route inside any active shooting air-defense zone.
func danger_segments(points: Array) -> Array:
	var zones = []
	for site in sim.air_defenses():
		var profile = sim.aa_profile(site.id)
		if profile.kind != "jammer":
			zones.append([site.position, profile.radius])
	var segments = []
	for i in range(points.size() - 1):
		var a: Vector2 = points[i]
		var b: Vector2 = points[i + 1]
		var steps = maxi(1, int(a.distance_to(b) / 0.6))
		for k in range(steps):
			var p0 = a.lerp(b, float(k) / steps)
			var p1 = a.lerp(b, float(k + 1) / steps)
			var mid = (p0 + p1) * 0.5
			for zone in zones:
				if mid.distance_to(zone[0]) <= zone[1]:
					segments.append([p0, p1])
					break
	return segments

func refresh_routes() -> void:
	_clear(route_layer)
	for path in sim.routes:
		var color = route_color(int(path.id))
		var selected = path.id == selected_route or path.id == hover_route
		var segments = danger_segments(path.points)
		if not segments.is_empty():
			var danger = ImmediateMesh.new()
			danger.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
			for seg in segments:
				_strip(danger, seg[0], seg[1], danger_width, route_lift - 0.04)
			danger.surface_end()
			_mesh_node(route_layer, danger, danger_color)
		if selected:
			var halo = color
			halo.a = 0.25
			_polyline(route_layer, path.points, halo, 1.1, false, route_lift - 0.02)
		_dashed(route_layer, path.points, color.darkened(0.08), selected_route_width if selected else route_width, true)
	_selection_ring.visible = not selected_target.is_empty()
	if _selection_ring.visible:
		var center: Vector2 = sim.base_position
		if selected_target != "base":
			var item = sim.target(selected_target)
			center = item.position if not item.is_empty() else sim.build_site(selected_target).get("position", center)
		_selection_ring.global_position = to_world(center)
		_selection_ring.global_basis = Basis.looking_at(up_at(center).cross(Vector3.RIGHT).normalized() if absf(up_at(center).dot(Vector3.RIGHT)) < 0.99 else Vector3.FORWARD, up_at(center)) if terrain is PlanetTerrain else Basis.IDENTITY

func show_draft(points: Array) -> void:
	_clear(draft_layer)
	if points.size() >= 2:
		var halo = draft_color
		halo.a = 0.35
		_polyline(draft_layer, points, halo, 0.9, false, route_lift)
		_dashed(draft_layer, points, draft_color, 0.34, false)

func _refresh_rings() -> void:
	var signature = ""
	for site in sim.air_defenses():
		var profile = sim.aa_profile(site.id)
		signature += "%s:%.2f;" % [site.id, profile.radius]
	signature += "base:%d" % sim.base_defense_level
	if signature == _ring_signature:
		return
	_ring_signature = signature
	for ring in _rings:
		ring.queue_free()
	_rings.clear()
	for site in sim.air_defenses():
		var profile = sim.aa_profile(site.id)
		var color = {"gun": gun_ring_color, "missile": missile_ring_color, "jammer": jammer_ring_color}[profile.kind]
		_rings.append(_ground_ring(site.position, profile.radius, color, ring_width))
	if sim.base_defense_level > 0 and not balance.base_defense_levels.is_empty():
		var level: BaseDefenseData = balance.base_defense_levels[mini(sim.base_defense_level, balance.base_defense_levels.size()) - 1]
		_rings.append(_ground_ring(sim.base_position, level.radius, base_defense_ring_color, ring_width))
	refresh_routes()

# ---------------------------------------------------------------- drones & sites

func spawn_drone_model(parent: Node, free: bool, build: Dictionary) -> DroneView:
	var scene = free_drone_scene if free else modular_drone_scene
	if not free:
		var frame = balance.frame(str(build.get("frame", "")))
		if frame != null and frame.drone_scene != null:
			scene = frame.drone_scene
	var node = scene.instantiate() as DroneView
	parent.add_child(node)
	if not free:
		node.apply_build(build, balance)
	return node

func _orient(node: Node3D, at: Vector2, toward: Vector2, lift: float) -> void:
	var pos = to_world(at, lift)
	var forward = to_world(toward, lift) - pos
	var up = up_at(at)
	if forward.length_squared() > 0.0001:
		var target = Transform3D(Basis.looking_at(forward.normalized(), up), pos)
		node.global_transform = node.global_transform.interpolate_with(target, 0.25) if node.is_inside_tree() else target
	else:
		node.global_position = pos

func sync(delta: float) -> void:
	_time += delta
	_refresh_rings()
	var live = {}
	for drone in sim.drones:
		live[drone.id] = true
		if not _drones.has(drone.id):
			var node = spawn_drone_model(drone_layer, drone.free, drone.build)
			var shadow: Sprite3D = null
			if show_shadows and drone_shadow_texture != null:
				shadow = Sprite3D.new()
				shadow.texture = drone_shadow_texture
				shadow.pixel_size = shadow_size
				shadow.axis = Vector3.AXIS_Y
				shadow.shaded = false
				shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				drone_layer.add_child(shadow)
			_drones[drone.id] = {"node": node, "shadow": shadow, "scale": free_drone_scale if drone.free else modular_drone_scale * balance.frame(str(drone.build.get("frame", ""))).map_scale}
			_orient(node, drone.position, drone.path[mini(drone.segment + 1, drone.path.size() - 1)], flight_altitude)
		var entry = _drones[drone.id]
		var node: DroneView = entry.node
		node.spin(delta)
		var next: Vector2 = drone.path[mini(drone.segment + 1, drone.path.size() - 1)]
		_orient(node, drone.position, next, flight_altitude + node.wobble(float(drone.id)).y)
		node.scale = Vector3.ONE * entry.scale
		if entry.shadow:
			entry.shadow.global_position = to_world(drone.position + Vector2(0.9, 0.9), 0.15)
		if not drone.free and drone.build.get("modules", []).has("boost") and booster_trail_scene != null and randf() < delta * 14:
			_spawn(booster_trail_scene, node.global_position + node.global_basis.z * 1.2)
	for id in _drones.keys():
		if not live.has(id):
			_drones[id].node.queue_free()
			if _drones[id].shadow:
				_drones[id].shadow.queue_free()
			_drones.erase(id)
	var hunters_live = {}
	for hunter in sim.hunters:
		hunters_live[hunter.id] = true
		if not _hunters.has(hunter.id) and hunter_scene != null:
			var node = hunter_scene.instantiate() as Node3D
			drone_layer.add_child(node)
			_hunters[hunter.id] = node
		if _hunters.has(hunter.id):
			var node: Node3D = _hunters[hunter.id]
			_orient(node, hunter.position, hunter.position + hunter.get("heading", (sim.base_position - hunter.position).normalized()) * 2.0, flight_altitude + 0.6)
			node.scale = Vector3.ONE * hunter_scale
			if node is DroneView:
				node.spin(delta)
	for id in _hunters.keys():
		if not hunters_live.has(id):
			_hunters[id].queue_free()
			_hunters.erase(id)
	for site in sites():
		if site.is_build_pad:
			site.set_built(sim.built_sites.has(site.build_id))
		elif site.is_player_base:
			site.set_upgrade_level(sim.base_defense_level)
	for obj in sim.targets:
		var site = site_for(obj.id)
		if site != null:
			site.visible = obj.active
			if obj.active:
				site.show_state(obj.hp / obj.max_hp, obj.hp <= 0, delta, func(at): _spawn(smoke_scene, at))
	if _selection_ring.visible:
		var pulse = 1.0 + sin(_time * 4.0) * 0.04
		_selection_ring.scale = Vector3(pulse, 1, pulse)
	for i in range(floaters.size() - 1, -1, -1):
		floaters[i].life -= delta
		if floaters[i].life <= 0:
			floaters.remove_at(i)

# ---------------------------------------------------------------- effects

func _spawn(scene: PackedScene, at: Vector3, delay: float = 0.0) -> Node3D:
	if scene == null:
		return null
	var node = scene.instantiate() as Node3D
	node.position = at
	if delay > 0:
		for sprite in node.find_children("*", "FxSprite", true, false):
			sprite.start_delay += delay
		if node is FxSprite:
			node.start_delay += delay
	fx_layer.add_child(node)
	if fx_layer.get_child_count() > 300:
		fx_layer.get_child(0).queue_free()
	return node

func _shot(from: Vector2, to: Vector2, kind: String, _hit: bool) -> void:
	var start = to_world(from, 2.6)
	var finish = to_world(to, flight_altitude)
	if kind == "tap":
		_spawn(muzzle_flash_scene, start)
		for k in range(tap_burst_rounds):
			var round = _spawn(tap_shot_scene, start, 0.045 * k)
			if round is FxSprite:
				round.target_position = finish + Vector3(randf_range(-0.3, 0.3), randf_range(-0.2, 0.2), randf_range(-0.3, 0.3))
		_spawn(flak_scene, finish, 0.12)
		return
	var projectile = _spawn(missile_scene if kind == "missile" else tracer_scene, start)
	if projectile is FxSprite:
		projectile.target_position = finish
	if kind == "missile":
		for k in range(missile_trail_puffs):
			_spawn(launch_dust_scene, start.lerp(finish, float(k) / missile_trail_puffs), 0.05 * k)

func _effect(kind: String, pos: Vector2) -> void:
	match kind:
		"hit":
			_spawn(explosion_scene, to_world(pos + Vector2(randf_range(-2, 2), randf_range(-1.5, 1.5)), 2.2))
		"miss":
			var p = pos + Vector2(randf_range(-6, 6), randf_range(3, 6))
			_spawn(small_explosion_scene, to_world(p, 0.5))
		"launch":
			_spawn(launch_dust_scene, to_world(pos + Vector2(randf_range(-2, 2), randf_range(-1, 1)), 1.0))
		"flak":
			_spawn(flak_scene, to_world(pos, flight_altitude), 0.2)
		"lost":
			_spawn(small_explosion_scene, to_world(pos, flight_altitude), 0.2)
		"deploy":
			_spawn(deploy_scene if deploy_scene else explosion_scene, to_world(pos, 1.0))
			_ring_signature = ""

func _floater(text: String, pos: Vector2, kind: String) -> void:
	var lift = flight_altitude if kind == "lost" else 5.0
	floaters.append({"text": text, "pos": to_world(pos + Vector2(randf_range(-1.5, 1.5), 0), lift), "kind": kind, "life": 1.4, "max": 1.4})
