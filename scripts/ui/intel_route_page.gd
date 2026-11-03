extends VBoxContainer
## Route page (ui/hud/intel_route_page.tscn).

@export var panel_title := "ROUTE"
@export var attached_row_scene: PackedScene
## Map units per second used for the "flight time" estimate.
@export var reference_speed := 18.0

var main: Node
var id := -1

func setup(game: Node, route_id: Variant) -> void:
	main = game
	id = int(route_id)
	panel_title = "ROUTE R%d" % id
	var sim = main.sim
	var path = sim.route(id)
	%Heading.text = "R%d  >  %s" % [id, sim.target(path.target).name.to_upper()]
	%Heading.add_theme_color_override("font_color", main.world.route_color(id))
	var length = sim.route_length(path.points)
	var exposure = {}
	for seg in main.world.danger_segments(path.points):
		var mid = (seg[0] + seg[1]) * 0.5
		for site in sim.air_defenses():
			var profile = sim.aa_profile(site.id)
			if profile.kind != "jammer" and mid.distance_to(site.position) <= profile.radius:
				exposure[profile.kind] = exposure.get(profile.kind, 0.0) + seg[0].distance_to(seg[1])
				break
	var exposed = 0.0
	var parts = []
	for kind in exposure:
		exposed += exposure[kind]
		parts.append("%s %.0f" % [kind, exposure[kind]])
	%Length.set_value("%.0f km" % length)
	%Exposure.set_value(("%.0f km · %s" % [exposed, ", ".join(parts)]) if exposed > 0 else "none", &"StatValueBad" if exposed > 0 else &"StatValueGood")
	%FlightTime.set_value("%.1f s" % (length / reference_speed))
	var reach = sim.balance.stats({"frame": sim.balance.starting_frames[0], "warhead": sim.balance.default_build_warhead, "modules": []}, sim.frame_level, sim.factory_level, sim.tech_mods()).range
	%Range.set_value("%.0f km" % reach, &"StatValueBad" if length > reach else &"StatValueGood")
	var any = false
	for item in sim.lines:
		if item.route == id:
			any = true
			var row = attached_row_scene.instantiate()
			%Attached.add_child(row)
			row.get_node("%Name").text = ("FREE DRONE" if item.free else "L%d %s" % [item.id, item.name]).to_upper()
			var line_id = int(item.id)
			row.get_node("%Detach").pressed.connect(func():
				main.sim.line(line_id).route = -1
				main.committed()
			)
	%EmptyHint.visible = not any
	%Redraw.pressed.connect(func(): main.sfx.play("click"); main.map_view.set_draw_mode(true, id))
	%Delete.pressed.connect(func(): main.sfx.play("click"); main.delete_selected_route())
