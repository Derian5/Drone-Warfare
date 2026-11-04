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
## Route whose end handle is being dragged to extend it (-1 = none).
var extend_route := -1
var hover_tip := -1
@export_group("Route handles")
## Pixels around a route's end where a drag extends the route.
@export var tip_grab_radius := 16.0
@export var tip_handle_radius := 7.0
@export var tip_handle_color := Color(1, 1, 1, 0.95)
var replace_id := -1
var hover_route := -1
var drag_hover := -1
var _drop_at := Vector2.ZERO
## Pixels around a route arrow where a dragged line is accepted.
@export var drop_radius := 48.0
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
	if drag_hover >= 0:
		var font = get_theme_default_font()
		var text = "Release: send to route R%d" % drag_hover
		var at = _drop_at + Vector2(18, -18)
		var w = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		draw_rect(Rect2(at - Vector2(8, 18), Vector2(w + 16, 26)), Color(0.05, 0.07, 0.09, 0.9))
		draw_rect(Rect2(at - Vector2(8, 18), Vector2(4, 26)), world.route_color(drag_hover))
		draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color.WHITE)
	for ring in _tap_rings:
		ring[1] -= _delta
	_tap_rings = _tap_rings.filter(func(r): return r[1] > 0)
	_place_labels()
	queue_redraw()

func _draw() -> void:
	draw_texture_rect(viewport.get_texture(), Rect2(Vector2.ZERO, size), false)
	if world != null and sim != null and not drawing and not sim.victory:
		for path in sim.routes:
			var end: Vector2 = path.points.back()
			if not world.is_facing(end):
				continue
			var at = world.map_to_screen(end)
			var color = world.route_color(int(path.id))
			var big = path.id == hover_tip or path.id == world.selected_route
			var r = tip_handle_radius * (1.35 if big else 1.0)
			draw_circle(at, r + 2.0, Color(0.05, 0.07, 0.09, 0.85))
			draw_circle(at, r, color)
			draw_arc(at, r + 1.0, 0, TAU, 24, tip_handle_color, 1.5, true)
			if big:
				draw_line(at + Vector2(-3, 0), at + Vector2(3, 0), Color(0.05, 0.07, 0.09), 2.0)
				draw_line(at + Vector2(0, -3), at + Vector2(0, 3), Color(0.05, 0.07, 0.09), 2.0)
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
		var building = sim.site_building_of(pad.id)
		pad_chip.show_pad(world.map_to_screen(pad.position) + site_chip_offset, pad, sim.built_sites.has(pad.id), building.display_name if building else "")
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
		if not chip.delete_requested.is_connected(_delete_route):
			chip.delete_requested.connect(_delete_route)
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
	extend_route = -1
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
			var tip = _tip_near(event.position)
			var launch = _launch_point(event.position)
			if tip >= 0 and not draw_mode:
				extend_route = tip
				press_position = event.position
				points = sim.route(tip).points.duplicate()
				accept_event()
				return
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
		elif extend_route >= 0 and not drawing:
			# A click on the handle without dragging selects what is there.
			var obj = world.target_near(event.position)
			if not obj.is_empty():
				main.select("target", obj)
			else:
				main.select("route", extend_route)
			extend_route = -1
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
		if extend_route >= 0 and not drawing and event.position.distance_to(press_position) > drag_threshold:
			drawing = true
			mouse_default_cursor_shape = Control.CURSOR_CROSS
			main.notice("Extending route R%d: release on the new target. Right click or Esc cancels." % extend_route)
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
			hover_tip = _tip_near(event.position)
			var over_hunter = world.hunter_near(event.position) >= 0 or hover_tip >= 0
			mouse_default_cursor_shape = Control.CURSOR_CROSS if _on_base(event.position) or over_hunter else (Control.CURSOR_POINTING_HAND if hover_route >= 0 or not hover_target.is_empty() else Control.CURSOR_ARROW)
	accept_event()

func _delete_route(id: int) -> void:
	main.sfx.play("click")
	main.delete_route(id)

## Route whose end handle is under the pointer, or -1.
func _tip_near(screen: Vector2) -> int:
	if world == null or sim == null:
		return -1
	var best = tip_grab_radius
	var found = -1
	for path in sim.routes:
		var end: Vector2 = path.points.back()
		if not world.is_facing(end):
			continue
		var d = screen.distance_to(world.map_to_screen(end))
		if d < best:
			best = d
			found = int(path.id)
	return found

func _finish_drawing(at: Vector2) -> void:
	drawing = false
	pressing_base = false
	var extending = extend_route
	extend_route = -1
	var obj = world.target_near(at)
	if obj.is_empty():
		main.notice("End the arrow on an enemy site. Try again." if extending < 0 else "Route not changed: release the extended arrow on an enemy site.")
		world.show_draft([])
		return
	points.append(sim.target(obj).position)
	var id = sim.add_route(points, obj, extending if extending >= 0 else replace_id)
	if extending >= 0 and id >= 0:
		world.show_draft([])
		main.select("route", id)
		main.notice("Route R%d extended to %s. Lines on it keep flying it." % [id, sim.target(obj).name])
		main.committed()
		return
	if id >= 0:
		set_draw_mode(false)
		main.select("route", id)
		main.notice("Route R%d ready. Drag an assembly line onto it." % id)
		main.committed()
	else:
		world.show_draft([])
		main.notice("Could not create the route. Stay inside the map; limit is %d arrows." % sim.balance.max_routes)

## Route a dragged line would be attached to: near the arrow, on its label,
## on its round end or on the site it attacks. Generous so it is easy to hit.
func _drop_route(at: Vector2) -> int:
	var id = world.route_near(at, drop_radius)
	if id >= 0:
		return id
	for key in _route_chips:
		var chip: Control = _route_chips[key]
		if chip.visible and chip.get_rect().grow(10).has_point(at):
			return int(key)
	var tip = _tip_near(at)
	if tip >= 0:
		return tip
	var obj = world.target_near(at)
	for path in sim.routes:
		if not obj.is_empty() and path.target == obj:
			return int(path.id)
	return -1

func _set_drag_hover(id: int, at: Vector2 = Vector2.ZERO) -> void:
	_drop_at = at
	if id != drag_hover:
		drag_hover = id
		world.hover_route = id
		world.refresh_routes()
	queue_redraw()

func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	if not (data is Dictionary and data.get("kind", "") == "line"):
		return false
	var id = _drop_route(at_position)
	_set_drag_hover(id, at_position)
	return id >= 0

func _drop_data(at_position: Vector2, data: Variant) -> void:
	var id = _drop_route(at_position)
	_set_drag_hover(-1)
	if sim.assign(int(data.line_id), id):
		main.select("route", id)
		main.committed()

func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		_set_drag_hover(-1)
