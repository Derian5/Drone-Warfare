extends SceneTree
## Dev helper: renders the main scene and saves a PNG. Usage:
## godot --path . --script res://tools/screenshot.gd -- out.png [map|editor|route|line|base|adapt|victory|fresh] [seconds]

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var args = OS.get_cmdline_user_args()
	var out = args[0] if args.size() > 0 else "user://shot.png"
	var mode = args[1] if args.size() > 1 else "map"
	var seconds = float(args[2]) if args.size() > 2 else 25.0
	root.size = Vector2i(1280, 720)
	var main = load("res://main.tscn").instantiate()
	main.persistence_enabled = false
	root.add_child(main)
	await process_frame
	var region_index = 0
	if mode.begins_with("r") and ":" in mode:
		region_index = int(mode.substr(1, 1)) - 1
		mode = mode.split(":")[1]
		for i in range(region_index):
			main.sim.region_states[main.campaign.regions[i].id] = {"stars": 1, "cleared": true, "best_time": 1.0}
		main.start_region(region_index)
		await process_frame
	var sim = main.sim
	if mode == "campaign":
		main.open_campaign()
	elif mode != "fresh":
		sim.credits = 900
		var id = sim.create_line("Striker", {"warhead": "fragment", "modules": ["armor"]})
		var mid = sim.base_position.lerp(sim.main_target().position, 0.5) + Vector2(0, 12)
		var r = sim.add_route([sim.base_position, mid, sim.main_target().position], "hq")
		sim.assign(id, r)
		sim.line(id).enabled = true
		main.committed()
		for i in range(int(seconds / 0.05)):
			sim.step(0.05)
	match mode:
		"editor":
			main.open_editor(1 if sim.paid_line_count() >= sim.line_slots else -1)
		"route":
			main.select("route", 2)
		"line":
			main.select("line", 1)
		"base":
			main.select("base", 0)
		"adapt":
			sim.pending_adaptation = "maneuver"
			sim.adaptation_timer = 12
		"frames":
			main.open_editor(1 if sim.paid_line_count() >= sim.line_slots else -1)
			sim.unlocked.append("heat_shield")
			main.editor._choose_frame(OS.get_environment("FRAME") if OS.has_environment("FRAME") else "glider")
			main.editor.hover = OS.get_environment("HOVER") if OS.has_environment("HOVER") else "heat_shield"
			main.editor._refresh()
		"pad":
			main.select("pad", sim.layout.build_sites[0].id)
		"orbit":
			main.world.orbit_drag(Vector2(-180, 40))
		"hunters":
			sim.upgrade("base_defense")
			sim.hunter_timer = 0.01
			for i in range(int(OS.get_environment("HUNTER_STEPS") if OS.has_environment("HUNTER_STEPS") else "60")):
				sim.step(0.05)
			main.paused = true
			print("hunters ", sim.hunters.map(func(h): return h.position), " stolen ", sim.totals.stolen)
		"victory":
			sim.main_target().hp = 1
			sim._impact({"target": "hq", "stats": {"damage": 50.0, "penetration": 0.0}, "line": 0})
	for i in range(60):
		await process_frame
	root.get_texture().get_image().save_png(out)
	print("saved ", out)
	quit(0)
