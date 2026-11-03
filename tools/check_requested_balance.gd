extends SceneTree
## Targeted resource and old-save compatibility check; no combat batch or player IO.

const Simulation = preload("res://scripts/sim/simulation.gd")
var checks = 0
var failures = 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var campaign = load("res://data/campaign.tres") as CampaignData
	var old_aa_hp = [650.0, 800.0, 900.0, 1000.0, 1100.0]
	var old_hq_hp = [600.0, 1900.0, 1600.0, 2600.0, 3000.0]
	var old_first_wave = [45.0, 40.0, 38.0, 35.0, 30.0]
	var old_wave_interval = [35.0, 32.0, 30.0, 28.0, 26.0]
	for i in range(campaign.regions.size()):
		var region: RegionData = campaign.regions[i]
		check(is_equal_approx(region.hunters.first_wave_after, old_first_wave[i] / 3), "First hunter wave /3: " + region.id)
		check(is_equal_approx(region.hunters.wave_interval, old_wave_interval[i] / 3), "Hunter wave interval /3: " + region.id)
		check(is_equal_approx(region.hunters.wave_interval_jitter, 5.0), "Hunter jitter /3: " + region.id)
		check(region.hunters.wave_interval > region.hunters.wave_interval_jitter, "Hunter intervals stay positive: " + region.id)
		var folder = "res://data/regions/%s/targets" % region.id
		for file in DirAccess.get_files_at(folder):
			if not file.ends_with(".tres"):
				continue
			var data = load(folder.path_join(file)) as TargetData
			if data.is_main_target:
				check(is_equal_approx(data.max_hp, old_hq_hp[i] / 5), "HQ health /5: " + region.id)
				check(data.respawn_time == 0, "HQ stays non-respawning: " + region.id)
			elif data.air_defense != null:
				var before = old_aa_hp[i] * (0.7 if data.air_defense.kind == AirDefenseData.Kind.JAMMER else 1.0)
				check(is_equal_approx(data.max_hp, before / 7), "AA health /7: " + region.id + "/" + file)
				check(is_equal_approx(data.respawn_time, 120.0), "AA repairs after 120s: " + region.id + "/" + file)
	var before_profiles = {"flak_gun": [16.0, 0.9], "heavy_flak": [16.0, 1.0], "sam_launcher": [34.0, 2.6], "hq_point_defense": [14.0, 0.8], "jammer": [0.0, 1.0]}
	for id in before_profiles:
		var data = load("res://data/air_defense/%s.tres" % id) as AirDefenseData
		check(is_equal_approx(data.damage, before_profiles[id][0] / 10), "Enemy AA damage /10: " + id)
		check(is_equal_approx(data.interval, before_profiles[id][1] / 5), "Enemy AA interval /5: " + id)
	var own_profiles = [[12.0, 0.8], [16.0, 0.65], [22.0, 0.5]]
	for i in range(3):
		var data = load("res://data/base_defense/level_%d.tres" % (i + 1)) as BaseDefenseData
		check(is_equal_approx(data.damage, own_profiles[i][0] / 10), "Player AA damage /10: level %d" % (i + 1))
		check(is_equal_approx(data.interval, own_profiles[i][1] / 5), "Player AA interval /5: level %d" % (i + 1))
	var first: RegionData = campaign.regions[0]
	var world = first.scene.instantiate()
	var layout = {"base": Vector2.ZERO, "targets": [], "build_sites": []}
	var guns = []
	for site in world.get_node("Sites").get_children():
		if not site is MapSite:
			continue
		if site.is_player_base:
			layout.base = Vector2(site.position.x, site.position.z)
		elif site.data != null:
			layout.targets.append({"data": site.data, "position": Vector2(site.position.x, site.position.z), "reserve": site.is_reserve})
			if site.data.air_defense != null:
				guns.append(site)
	check(guns.size() == 1, "First region has exactly one AA, including reserves and HQ guns")
	if guns.size() == 1:
		check(guns[0].data.air_defense == load("res://data/air_defense/flak_gun.tres"), "Only first-region AA is Flak Gun")
		check(not guns[0].is_reserve, "Flak Gun is initially active")
	var rules = load("res://data/balance.tres") as GameBalance
	var sim = Simulation.new(rules, campaign)
	sim.start_region(0, layout)
	var saved = sim.snapshot()
	# Emulate a save from before first-region SAM/reserve removal.
	saved.targets.append({"id": "sam_a", "hp": 650.0, "max_hp": 650.0, "active": true})
	saved.routes.append({"id": 900, "target": "sam_a", "points": []})
	saved.drones.append({"id": 900, "target": "sam_a"})
	saved.lines[0].route = 900
	saved.pending_reserve = "gun_r1"
	saved.pending_adaptation = "forward_battery"
	saved.adaptation_timer = 10.0
	check(sim.restore(saved), "Existing save restores after layout change")
	check(sim.target("sam_a").is_empty() and sim.route(900).is_empty(), "Removed target and its route are dropped")
	check(sim.drones.is_empty() and sim.line(0).route == -1, "Invalid flights removed and line awaits a new route")
	check(sim.pending_reserve.is_empty() and sim.pending_adaptation.is_empty(), "Removed reserve cannot deploy from an old save")
	world.free()
	print("BALANCE CHANGE: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
