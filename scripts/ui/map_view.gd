class_name MapView
extends Control
## Shows the battlefield SubViewport at native resolution, places 2D map labels
## (scenes in ui/map/) over it, and handles route drawing and line drag-and-drop.

@export_group("Label scenes")
@export var site_chip_scene: PackedScene
@export var route_chip_scene: PackedScene
@export var floater_scene: PackedScene
@export var hunter_marker_scene: PackedScene = preload("res://ui/map/hunter_marker.tscn")
@export_group("Placement")
@export var site_chip_offset := Vector2(0, 40)
@export var route_chip_offset := Vector2(10, -10)
@export var floater_rise := 34.0
@export_group("Drawing")
## Map units around the base where a drag starts a route.
@export var base_grab_radius := 9.0
## Pixels the pointer must move before a press on the base becomes a drawing.
@export var drag_threshold := 8.0
@export var max_render_scale := 2.0

signal feedback(text: String)

@onready var viewport: SubViewport = $Viewport
@onready var overlay: Control = $Overlay
@onready var draw_hint: Control = %DrawHint
@onready var draw_hint_label: Label = %DrawHintLabel
@onready var base_tip: Control = %BaseTip

var main: Node
var world: Battlefield
var sim: RefCounted
var drawing := false
var pressing_base := false
var press_position := Vector2.ZERO
var points: Array = []
var draw_mode := false
## Pressed on empty map space (planet: dragging rotates the globe).
var pressing_empty := false
var replace_id := -1
var hover_route := -1
var drag_hover := -1
var _site_chips := {}
var _route_chips := {}
var _floaters: Array = []
var _hunter_markers := {}
## Click/tap "shot" rings drawn on the map: [position, time left].
var _tap_rings: Array = []
@export var tap_ring_color := Color(0.6, 1, 1, 0.95)
@export var tap_ring_time := 0.28

func setup(game: Node) -> void:
	main = game
	sim = game.sim
	resized.connect(_fit)
	attach_world(game.world)

## Called when a new region scene is loaded.
func attach_world(new_world: Battlefield) -> void:
	world = new_world
	for store in [_site_chips, _route_chips, _hunter_markers]:
		for chip in store.values():
			chip.queue_free()
		store.clear()
	_fit()

func render_scale() -> float:
	var logical = get_viewport_rect().size
	var window = Vector2(get_window().size)
	if logical.x <= 0 or window.x <= 0:
		return 1.0
	return clampf(window.x / logical.x, 1.0, max_render_scale)

func _fit() -> void:
	if size.x < 4 or size.y < 4:
		return
	var s = render_scale()
	viewport.size = Vector2i(maxi(4, int(size.x * s)), maxi(4, int(size.y * s)))
	if world != null:
		world.set_view(Vector2(viewport.size), s)

func _process(_delta: float) -> void:
	if world == null:
		return
	if absf(world.view_scale - float(viewport.size.x) / maxf(1.0, size.x)) > 0.01:
		_fit()
	sim = main.sim
	for ring in _tap_rings:
		ring[1] -= _delta
	_tap_rings = _tap_rings.filter(func(r): return r[1] > 0)
	_place_labels()
	queue_redraw()

func _draw() -> void:
	draw_texture_rect(viewport.get_texture(), Rect2(Vector2.ZERO, size), false)
	for ring in _tap_rings:
		var k = 1.0 - ring[1] / tap_ring_time
		draw_arc(ring[0], 8 + k * 26, 0, TAU, 32, Color(tap_ring_color, tap_ring_color.a * (1.0 - k)), 3.0, true)
		for a in range(4):
			var dir = Vector2.RIGHT.rotated(a * PI / 2 + PI / 4)
			draw_line(ring[0] + dir * (4 + k * 10), ring[0] + dir * (12 + k * 22), Color(tap_ring_color, 1.0 - k), 2.0, true)
	if draw_mode and not drawing:
		var base = world.map_to_screen(sim.base_position)
		var pulse = 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.006)
		draw_arc(base, 30 + pulse * 8, 0, TAU, 48, Color(0.12, 0.72, 0.77, 0.9 - pulse * 0.5), 3)

# ---------------------------------------------------------------- labels

func _chip(store: Dictionary, key: Variant, scene: PackedScene) -> Control:
	if not store.has(key):
		var node = scene.instantiate() as Control
		overlay.add_child(node)
		store[key] = node
	return store[key]

func _place_labels() -> void:
	var base_chip = _chip(_site_chips, "base", site_chip_scene)
	base_chip.show_base(world.map_to_screen(sim.base_position) + site_chip_offset)
	base_chip.visible = world.is_facing(sim.base_position)
	var live = {"base": true}
	for pad in sim.layout.get("build_sites", []):
		live[pad.id] = true
		var pad_chip = _chip(_site_chips, pad.id, site_chip_scene)
		pad_chip.show_pad(world.map_to_screen(pad.position) + site_chip_offset, pad, sim.built_sites.has(pad.id))
		pad_chip.visible = world.is_facing(pad.position)
	for obj in sim.active_targets():
		live[obj.id] = true
		var chip = _chip(_site_chips, obj.id, site_chip_scene)
		var data = sim.target_data(obj.id)
		chip.show_target(world.map_to_screen(obj.position) + site_chip_offset, obj, data)
		chip.visible = world.is_facing(obj.position)
	for key in _site_chips.keys():
		if not live.has(key):
			_site_chips[key].queue_free()
			_site_chips.erase(key)
	var routes_live = {}
	for path in sim.routes:
		routes_live[path.id] = true
		var chip = _chip(_route_chips, path.id, route_chip_scene)
		var tokens = []
		for item in sim.lines:
			if item.route == path.id:
				tokens.append("FREE" if item.free else "L%d" % item.id)
		var highlight = path.id == world.selected_route or path.id == hover_route or path.id == drag_hover
		var label_point = _route_label_point(path.points)
		chip.show_route(world.map_to_screen(label_point) + route_chip_offset, int(path.id), world.route_color(int(path.id)), tokens, highlight)
		chip.visible = world.is_facing(label_point)
	for key in _route_chips.keys():
		if not routes_live.has(key):
			_route_chips[key].queue_free()
			_route_chips.erase(key)
	var hunters_live = {}
	var defense = sim._base_defense()
	for hunter in sim.hunters:
		hunters_live[hunter.id] = true
		var marker = _chip(_hunter_markers, hunter.id, hunter_marker_scene)
		var crippled = defense != null and hunter.hp <= hunter.max_hp * defense.min_hp_fraction + 0.01
		marker.show_hunter(world.world_to_screen(world.to_world(hunter.position, world.flight_altitude + 0.6)), size, hunter, crippled)
		marker.visible = world.is_facing(hunter.position)
	for key in _hunter_markers.keys():
		if not hunters_live.has(key):
			_hunter_markers[key].queue_free()
			_hunter_markers.erase(key)
	while _floaters.size() < world.floaters.size():
		var label = floater_scene.instantiate()
		overlay.add_child(label)
		_floaters.append(label)
	for i in range(_floaters.size()):
		var node = _floaters[i]
		node.visible = i < world.floaters.size()
		if node.visible:
			var item = world.floaters[i]
			var t = 1.0 - item.life / item.max
			node.show_text(item.text, item.kind, world.world_to_screen(item.pos) + Vector2(0, -t * floater_rise), 1.0 - pow(t, 3.0))
	var needs_tip = not sim.victory and not drawing and (draw_mode or not sim.routes.any(func(r): return r.target == main.main_target_id()))
	base_tip.visible = needs_tip
	if needs_tip:
		base_tip.position = world.map_to_screen(sim.base_position) - Vector2(base_tip.size.x / 2, 72)
	draw_hint.visible = drawing or draw_mode
	if draw_hint.visible:
		draw_hint_label.text = "Release on a target  ·  right click or Esc to cancel" if drawing else "REDRAW  ·  drag from your base to a target  ·  Esc to cancel"

func _route_label_point(pts: Array) -> Vector2:
	var total = 0.0
	for i in range(pts.size() - 1):
		total += pts[i].distance_to(pts[i + 1])
	var walked = 0.0
	for i in range(pts.size() - 1):
		var seg = pts[i].distance_to(pts[i + 1])
		if walked + seg >= total * 0.45:
			return pts[i].lerp(pts[i + 1], (total * 0.45 - walked) / maxf(seg, 0.001))
		walked += seg
	return pts[0]

# ---------------------------------------------------------------- drawing routes

## draw_mode is only used for REDRAW; new routes are drawn by dragging from the base.
func set_draw_mode(enabled: bool, editing: int = -1) -> void:
	draw_mode = enabled
	replace_id = editing if enabled else -1
	drawing = false
	pressing_base = false
	points.clear()
	if world != null:
		world.show_draft([])
	mouse_default_cursor_shape = Control.CURSOR_ARROW
	if enabled:
		main.notice("Drag from YOUR BASE along the new path and release on a target. Esc cancels.")

func is_busy() -> bool:
	return draw_mode or drawing

## Launch point (base or built forward pad) under the pointer, or null.
func _launch_point(screen: Vector2) -> Variant:
	var at = world.screen_to_map(screen)
	for point in sim.launch_points():
		if at.distance_to(point) < base_grab_radius:
			return point
	return null

func _on_base(screen: Vector2) -> bool:
	return _launch_point(screen) != null

func _gui_input(event: InputEvent) -> void:
	if world == null:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		if is_busy():
			set_draw_mode(false)
			main.notice("Route drawing cancelled.")
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var hunter = world.hunter_near(event.position)
			if hunter >= 0 and not draw_mode:
				if sim.hit_hunter(hunter):
					main.sfx.play("shot")
					_tap_rings.append([event.position, tap_ring_time])
				accept_event()
				return
			var launch = _launch_point(event.position)
			if launch != null:
				pressing_base = true
				press_position = event.position
				points = [launch]
			elif draw_mode:
				main.notice("Start the route on your base.")
			else:
				pressing_empty = world.orbit_camera
				press_position = event.position
				var obj = world.target_near(event.position)
				var pad = world.pad_near(event.position)
				var route_id = world.route_near(event.position)
				if not obj.is_empty():
					main.select("target", obj)
				elif not pad.is_empty():
					main.select("pad", pad)
				elif route_id >= 0:
					main.select("route", route_id)
		elif pressing_empty:
			pressing_empty = false
			mouse_default_cursor_shape = Control.CURSOR_ARROW
		elif drawing:
			_finish_drawing(event.position)
		elif pressing_base:
			pressing_base = false
			if points[0].distance_to(sim.base_position) < 0.5:
				main.select("base", 0)
			else:
				for pad in sim.layout.get("build_sites", []):
					if pad.position.distance_to(points[0]) < 0.5:
						main.select("pad", pad.id)
	if event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		world.zoom_by(0.9 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.1)
	if event is InputEventMagnifyGesture:
		world.zoom_by(1.0 / maxf(0.01, event.factor))
	if event is InputEventMouseMotion and pressing_empty and (event.button_mask & MOUSE_BUTTON_MASK_LEFT):
		if event.position.distance_to(press_position) > drag_threshold:
			mouse_default_cursor_shape = Control.CURSOR_MOVE
			world.orbit_drag(event.relative)
		return
	if event is InputEventMouseMotion:
		if pressing_base and not drawing and event.position.distance_to(press_position) > drag_threshold:
			drawing = true
			mouse_default_cursor_shape = Control.CURSOR_CROSS
		if drawing:
			var point: Vector2 = world.screen_to_map(event.position)
			if point.x < 0 or point.y < 0 or point.x > sim.MAP_SIZE.x or point.y > sim.MAP_SIZE.y:
				return
			if points.size() < 100 and point.distance_to(points.back()) > 1.6:
				points.append(point)
				world.show_draft(points)
		else:
			var hover_target = world.target_near(event.position)
			hover_route = -1 if not hover_target.is_empty() else world.route_near(event.position)
			var over_hunter = world.hunter_near(event.position) >= 0
			mouse_default_cursor_shape = Control.CURSOR_CROSS if _on_base(event.position) or over_hunter else (Control.CURSOR_POINTING_HAND if hover_route >= 0 or not hover_target.is_empty() else Control.CURSOR_ARROW)
	accept_event()

func _finish_drawing(at: Vector2) -> void:
	drawing = false
	pressing_base = false
	var obj = world.target_near(at)
	if obj.is_empty():
		main.notice("End the arrow on an enemy site. Try again.")
		world.show_draft([])
		return
	points.append(sim.target(obj).position)
	var id = sim.add_route(points, obj, replace_id)
	if id >= 0:
		set_draw_mode(false)
		main.select("route", id)
		main.notice("Route R%d ready. Drag an assembly line onto it." % id)
		main.committed()
	else:
		world.show_draft([])
		main.notice("Could not create the route. Stay inside the map; limit is %d arrows." % sim.balance.max_routes)

func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	var ok = data is Dictionary and data.get("kind", "") == "line" and world.route_near(at_position) >= 0
	drag_hover = world.route_near(at_position) if ok else -1
	return ok

func _drop_data(at_position: Vector2, data: Variant) -> void:
	drag_hover = -1
	var id = world.route_near(at_position)
	if sim.assign(int(data.line_id), id):
		main.select("route", id)
		main.committed()

func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		drag_hover = -1
