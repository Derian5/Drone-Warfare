extends SceneTree
## Balance bot: plays the whole campaign headless with several strategies and prints a report.
## godot --headless --path . --script res://tools/balance_bot.gd [-- strategy_name]
##
## Each strategy is a simple scripted player: buys line slots, builds drones, draws a route
## (direct, detour around air defense, or from a forward pad), taps hunters, buys base AA and techs.

const Simulation = preload("res://scripts/sim/simulation.gd")
const STEP = 0.1
const REGION_TIME_LIMIT = 1500.0

var STRATEGIES = {
	"armor_direct": {"builds": [["fragment", ["armor"]], ["fragment", ["armor", "boost"]], ["fragment", ["payload"]], ["fragment", ["armor"]], ["fragment", ["armor", "boost"]]], "route": "direct", "tap": 0.8, "base_aa": true},
	"armor_detour": {"builds": [["fragment", ["armor"]], ["fragment", ["armor", "boost"]], ["fragment", ["payload"]], ["fragment", ["armor"]], ["fragment", ["armor", "boost"]]], "route": "detour", "tap": 0.8, "base_aa": true},
	"adaptive": {"builds": "adaptive", "route": "detour", "tap": 2.0, "base_aa": true, "waves": true},
	"adaptive_lazy_taps": {"builds": "adaptive", "route": "detour", "tap": 0.1, "base_aa": true, "waves": true},
	"passive": {"builds": [["fragment", ["armor"]]], "route": "direct", "tap": 0.0, "base_aa": false},
}

var rng = RandomNumberGenerator.new()
var _snap = {}
var _saving = false
## line id -> [lost, hit] in the last minute window (for copying the best build).
var _recent = {}

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var args = OS.get_cmdline_user_args()
	var names = args if not args.is_empty() else STRATEGIES.keys()
	var report = []
	for name in names:
		report.append_array(await _play(name, STRATEGIES[name]))
	print("\n=== BALANCE REPORT ===")
	print("strategy           region            result  time  stars losses stolen adapt credits tapped strikes")
	for r in report:
		print("%-18s %-17s %-7s %5d  %d     %4d   %5d   %d    %6d  %4d  %4d" % [r.strategy, r.region, r.result, r.time, r.stars, r.losses, r.stolen, r.adapt, r.credits, r.tapped, r.strikes])
	quit()

func _play(name: String, strategy: Dictionary) -> Array:
	rng.seed = int(OS.get_environment("BOT_SEED")) if OS.has_environment("BOT_SEED") else 99
	var balance: GameBalance = load("res://data/balance.tres")
	var campaign: CampaignData = load("res://data/campaign.tres")
	var sim = Simulation.new(balance, campaign)
	var rows = []
	var region_count = int(OS.get_environment("BOT_REGIONS")) if OS.has_environment("BOT_REGIONS") else campaign.regions.size()
	for index in range(region_count):
		var region: RegionData = campaign.regions[index]
		sim.rng.seed = rng.seed + index
		var world = region.scene.instantiate()
		root.add_child(world)
		await process_frame
		sim.start_region(index, world.layout())
		_snap.clear()
		_recent.clear()
		_saving = false
		var stolen_before = sim.totals.stolen
		var strikes_before = int(sim.totals.get("strikes", 0))
		var tapped_before = int(sim.totals.get("hunters_tapped", 0))
		var t = 0.0
		var think = 0.0
		while not sim.victory and t < REGION_TIME_LIMIT:
			sim.step(STEP)
			t += STEP
			think -= STEP
			_tap_hunters(sim, strategy.tap)
			if think <= 0:
				think = 1.0
				_think(sim, strategy, world)
				if OS.get_environment("BOT_DEBUG") == str(index) and int(t) % 60 == 0:
					var info = []
					for l in sim.lines:
						info.append("%s:%s r%d L%d H%d %s" % [l.id, l.build.get("warhead", "-") + "+" + ",".join(l.build.get("modules", [])), l.route, l.lost, l.hit, sim.status(l)])
					print("t=%d hq=%d cr=%d lost=%d  %s" % [t, sim.main_target().hp, sim.credits, sim.run_losses, " | ".join(info)])
		rows.append({"strategy": name, "region": region.display_name, "result": "WIN" if sim.victory else "STUCK", "time": int(t), "stars": sim.result.get("stars", 0), "losses": sim.run_losses, "stolen": int(sim.totals.stolen - stolen_before), "adapt": sim.adaptations.size(), "credits": int(sim.credits), "strikes": int(sim.totals.get("strikes", 0)) - strikes_before, "tapped": int(sim.totals.get("hunters_tapped", 0)) - tapped_before})
		_buy_techs(sim, campaign)
		world.queue_free()
		await process_frame
		if not sim.victory:
			break
	return rows

func _tap_hunters(sim, rate: float) -> void:
	for hunter in sim.hunters:
		if rng.randf() < rate * STEP:
			sim.hit_hunter(hunter.id)

func _buy_techs(sim, campaign: CampaignData) -> void:
	for tech in campaign.techs:
		if sim.tech_available(tech) and sim.tech_points >= tech.cost:
			sim.buy_tech(tech.id)

func _builds(sim, strategy: Dictionary) -> Array:
	if strategy.builds is Array:
		return strategy.builds
	# Adaptive: answer whatever the enemy has adapted against.
	var adapted = sim.adaptations
	var main = sim.target_data(sim.main_target().id)
	var warhead = "piercing" if sim.target_armor(sim.main_target().id) >= 60 else "fragment"
	var a = ["fragment", ["armor", "boost"]]
	var b = [warhead, ["maneuver", "payload"]]
	var c = ["fragment", ["decoy_flares", "boost"]]
	if adapted.has("heavy_interceptors"):
		a = ["fragment", ["maneuver", "boost"]]
	if adapted.has("precision_tracking"):
		b = [warhead, ["armor", "payload"]]
	var kinds = sim.air_defenses().map(func(t): return sim.aa_profile(t.id).kind)
	if kinds.has("jammer"):
		c = ["fragment", ["ew_pod", "decoy_flares" if kinds.has("missile") else "armor"]]
	if kinds.count("missile") >= 2 and not adapted.has("flare_discrimination"):
		a = ["fragment", ["decoy_flares", "boost"]]
	return [a, b, c, a, b]

func _think(sim, strategy: Dictionary, world) -> void:
	var builds = _builds(sim, strategy)
	# Wave play: when the HQ out-repairs a starving economy, pause paid lines and bank credits
	# for one combined assault (what a sensible player does against regeneration).
	var main = sim.main_target()
	if strategy.get("waves", false):
		if not _saving and sim.credits < sim.reserve + 40 and main.hp > main.max_hp * 0.85:
			_saving = true
		elif _saving and sim.credits > sim.reserve + 4 * sim.lines.filter(func(l): return not l.free).reduce(func(acc, l): return acc + sim.line_stats(l).cost, 0):
			_saving = false
	# Base air defense once hunters show up.
	if strategy.base_aa and sim.upgrade_price("base_defense") >= 0 and sim.credits > sim.upgrade_price("base_defense") * 2 + 200:
		sim.upgrade("base_defense")
	# Open line slots and create/refresh lines.
	while sim.paid_line_count() >= sim.line_slots and sim.next_slot_price() >= 0 and sim.credits > sim.next_slot_price() + 250 and sim.paid_line_count() < builds.size():
		sim.buy_line_slot()
	for i in range(builds.size()):
		var warhead = builds[i][0].replace("payload_", "")
		var frame_id = sim.available_frames().back()
		var build = {"frame": frame_id, "warhead": warhead, "modules": builds[i][1].duplicate().filter(func(m): return sim.balance.fits(m, frame_id))}
		for id in [warhead] + build.modules:
			if not sim.unlocked.has(id) and sim.available_modules().has(id) and sim.credits > sim.balance.module(id).unlock_cost + 150:
				sim.unlock(id)
		build.modules = build.modules.filter(func(id): return sim.unlocked.has(id))
		if not sim.unlocked.has(warhead) or not sim.balance.fits(warhead, frame_id):
			build.warhead = "fragment"
		while build.modules.size() > sim.balance.slots(sim.frame_level, frame_id):
			build.modules.pop_back()
		var line_id = i + 1
		# Copy the build of the best-performing line onto a line that keeps dying.
		if strategy.get("copy_best", false) and _recent.has(line_id):
			var mine = _recent[line_id]
			if mine[0] >= 3 and mine[1] * 3 <= mine[0]:
				var best_id = -1
				var best_score = -1.0
				for other_id in _recent:
					var r = _recent[other_id]
					var score = float(r[1]) / float(r[0] + 1)
					if score > best_score and r[1] >= 2 and not sim.line(other_id).is_empty() and not sim.line(other_id).free:
						best_score = score
						best_id = other_id
				if best_id >= 0 and best_id != line_id:
					build = sim.line(best_id).build.duplicate(true)
		if sim.line(line_id).is_empty():
			if sim.paid_line_count() < sim.line_slots:
				line_id = sim.create_line("Bot %d" % line_id, build)
			else:
				continue
		else:
			sim.update_build(line_id, "Bot %d" % line_id, build)
		var item = sim.line(line_id)
		if item.is_empty():
			continue
		# Re-plan a route that keeps losing drones without hits (e.g. after a reserve site opened).
		var snap = _snap.get(line_id, [item.lost, item.hit, sim.elapsed])
		if sim.elapsed - snap[2] >= 60.0:
			_recent[line_id] = [item.lost - snap[0], item.hit - snap[1]]
			if item.lost - snap[0] >= 3 and item.hit - snap[1] == 0 and item.route >= 0 and strategy.route == "detour":
				sim.delete_route(item.route)
			snap = [item.lost, item.hit, sim.elapsed]
		_snap[line_id] = snap
		if item.route < 0 or sim.route(item.route).is_empty():
			var route_id = _route(sim, strategy.route)
			if route_id >= 0:
				sim.assign(line_id, route_id)
		if sim.route_length(sim.route(item.route).get("points", [])) > sim.line_stats(item).range:
			if sim.balance.fits("fuel_tank", frame_id) and (sim.unlocked.has("fuel_tank") or (sim.available_modules().has("fuel_tank") and sim.unlock("fuel_tank"))):
				build.modules = ["fuel_tank"] + build.modules.slice(0, sim.balance.slots(sim.frame_level, frame_id) - 1)
				sim.update_build(line_id, "Bot", build)
			for pad in sim.layout.build_sites:
				if not sim.built_sites.has(pad.id) and sim.credits > pad.price + 100:
					sim.build_pad(pad.id)
					sim.delete_route(item.route)
					break
		item.enabled = not _saving
	if _saving:
		return
	if sim.credits > 700 and sim.upgrade_price("factory") >= 0:
		sim.upgrade("factory")
	if sim.credits > 600 and sim.upgrade_price("frame") >= 0:
		sim.upgrade("frame")
	if sim.overdrive_cooldown <= 0 and sim.credits > 300:
		sim.activate_overdrive()

func _route(sim, mode: String) -> int:
	var main = sim.main_target()
	var start: Vector2 = sim.launch_points().back()
	var goal: Vector2 = main.position
	if mode == "direct":
		return sim.add_route([start, goal], main.id)
	var best_points = [start, goal]
	var best_score = _exposure(sim, best_points)
	var normal = (goal - start).normalized().orthogonal()
	for offset in [-30, -22, -15, -8, 8, 15, 22, 30]:
		for t in [0.35, 0.5, 0.65]:
			var mid = start.lerp(goal, t) + normal * offset
			mid = mid.clamp(Vector2(1, 1), sim.MAP_SIZE - Vector2(1, 1))
			var pts = [start, mid, goal]
			var length = sim.route_length(pts)
			var score = _exposure(sim, pts) + length * 0.05
			if score < best_score and length < 125:
				best_score = score
				best_points = pts
	return sim.add_route(best_points, main.id)

func _exposure(sim, points: Array) -> float:
	var total = 0.0
	for i in range(points.size() - 1):
		var a: Vector2 = points[i]
		var b: Vector2 = points[i + 1]
		var steps = maxi(1, int(a.distance_to(b)))
		for k in range(steps):
			var p = a.lerp(b, (k + 0.5) / steps)
			for site in sim.air_defenses():
				var prof = sim.aa_profile(site.id)
				if prof.kind != "jammer" and p.distance_to(site.position) < prof.radius and (not prof.los or sim._line_of_sight(site.position, p)):
					total += a.distance_to(b) / steps * prof.damage / prof.interval * 0.1
	return total
