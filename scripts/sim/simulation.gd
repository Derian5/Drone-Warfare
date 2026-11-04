extends RefCounted
## Mutable game state. Rendering and UI never own gameplay timers.
## Global rules: GameBalance. Region rules: RegionData. Site placement: the region scene.

signal notice(text: String)
signal effect(kind: String, position: Vector2)
signal floater(text: String, position: Vector2, kind: String)
## Air-defense shot for visuals: from site to drone; kind = "gun" / "missile".
signal shot(from: Vector2, to: Vector2, kind: String, hit: bool)
signal region_finished(result: Dictionary)

const SAVE_PATH = "user://drone_warfare_v4.json"
const MAP_SIZE = Vector2(100, 68)
const VERSION = 4

var balance: GameBalance
var campaign: CampaignData
var region_data: RegionData
## {"base": Vector2, "waypoint": Vector2, "targets": [...], "build_sites": [...], "height": Callable}
var layout: Dictionary = {}
var base_position := Vector2.ZERO

# ---- persistent (carried between regions)
var credits = 500.0
var reserve = 100
var frame_level = 0
var factory_level = 0
var line_slots = 1
var base_defense_level = 0
## "Upgrade air defense" level: base AA damage × (base_aa_boost + 1).
var base_aa_boost = 0
var unlocked: Array = []
var lines: Array = []
var next_line = 1
var techs: Array = []
var tech_points = 0
var region_index = 0
var region_states: Dictionary = {}
var totals = {"income": 0.0, "spent": 0.0, "launched": 0, "hit": 0, "lost": 0, "miss": 0, "stolen": 0.0}

# ---- current region run
var targets: Array = []
var routes: Array = []
var drones: Array = []
var hunters: Array = []
var built_sites: Array = []
## Build site id -> SiteBuildingData id ("pad", "aa_tower", "income_hub").
var site_buildings: Dictionary = {}
var site_gun_timers: Dictionary = {}
var next_route = 1
var next_drone = 1
var elapsed = 0.0
var run_losses = 0
var overdrive = 0.0
var overdrive_cooldown = 0.0
var victory = false
var result: Dictionary = {}
var adaptations: Array = []
var pending_adaptation = ""
var pending_reserve = ""
var adaptation_timer = 0.0
var adaptation_lock = 0.0
var observations: Array = []
var hunter_timer = 0.0
var base_gun_timer = 0.0
var rng = RandomNumberGenerator.new()

func _init(rules: GameBalance, campaign_data: CampaignData) -> void:
	balance = rules
	campaign = campaign_data
	credits = balance.starting_credits
	reserve = balance.starting_reserve
	unlocked = Array(balance.starting_unlocked)
	line_slots = 0
	for price in balance.line_slot_prices:
		if price <= 0:
			line_slots += 1
	rng.seed = 741051
	lines.append(_line(0, "Free Drone", {}, -1, true))

# ================================================================ regions

func region_count() -> int:
	return campaign.regions.size() if campaign != null else 1

func region_unlocked(index: int) -> bool:
	if index == 0:
		return true
	var previous = campaign.regions[index - 1]
	return region_states.get(previous.id, {}).get("cleared", false)

## Starts (or restarts) a region with the given scene layout. Persistent progress is kept.
func start_region(index: int, site_layout: Dictionary) -> void:
	region_index = clampi(index, 0, region_count() - 1)
	region_data = campaign.regions[region_index] if campaign != null and not campaign.regions.is_empty() else null
	layout = site_layout
	base_position = layout.base
	targets.clear()
	routes.clear()
	drones.clear()
	hunters.clear()
	built_sites.clear()
	site_buildings.clear()
	site_gun_timers.clear()
	adaptations.clear()
	observations.clear()
	pending_adaptation = ""
	pending_reserve = ""
	adaptation_timer = 0
	adaptation_lock = 0
	next_route = 1
	elapsed = 0.0
	run_losses = 0
	overdrive = 0
	overdrive_cooldown = 0
	victory = false
	result = {}
	base_gun_timer = 0
	var hunter = _hunter_data()
	hunter_timer = hunter.first_wave_after if hunter != null and hunter.enabled else -1.0
	_setup_targets()
	for item in lines:
		item.route = -1
		item.order = {}
		item.disabled = 0.0
	line(0).route = _free_route()
	line(0).enabled = true

func _setup_targets() -> void:
	var hp_mult = region_data.hp_multiplier if region_data else 1.0
	targets = []
	for site in layout.targets:
		var data: TargetData = site.data
		targets.append({"id": data.id, "name": data.display_name, "position": site.position, "hp": data.max_hp * hp_mult, "max_hp": data.max_hp * hp_mult, "armor": data.armor, "rate": data.payout_rate * (region_data.payout_multiplier if region_data else 1.0), "respawn": 0.0, "since_hit": 999.0, "gun_timer": 0.0, "reserve": site.get("reserve", false), "active": not site.get("reserve", false)})

func _free_route() -> int:
	var depot = target(balance.free_line_target)
	if depot.is_empty():
		for item in targets:
			if item.active and not target_data(item.id).is_main_target:
				depot = item
				break
	if depot.is_empty():
		return -1
	return add_route([base_position, layout.get("waypoint", base_position.lerp(depot.position, 0.5)), depot.position], depot.id)

func _hunter_data() -> HunterData:
	return region_data.hunters if region_data != null else null

# ================================================================ lookups

func target_data(id: String) -> TargetData:
	for site in layout.get("targets", []):
		if site.data.id == id:
			return site.data
	return null

func target(id: String) -> Dictionary:
	for item in targets:
		if item.id == id:
			return item
	return {}

func active_targets() -> Array:
	return targets.filter(func(t): return t.active)

func main_target() -> Dictionary:
	for site in layout.get("targets", []):
		if site.data.is_main_target:
			return target(site.data.id)
	return {}

func air_defenses() -> Array:
	return targets.filter(func(t): return t.active and t.hp > 0 and target_data(t.id).air_defense != null)

func line(id: int) -> Dictionary:
	for item in lines:
		if item.id == id:
			return item
	return {}

func route(id: int) -> Dictionary:
	for item in routes:
		if item.id == id:
			return item
	return {}

func launch_points() -> Array:
	var points = [base_position]
	for site in layout.get("build_sites", []):
		if built_sites.has(site.id) and building_kind(site.id) == SiteBuildingData.Kind.LAUNCH_PAD:
			points.append(site.position)
	return points

## Kind of the building on a build site (-1 = nothing built).
func building_kind(site_id: String) -> int:
	if not built_sites.has(site_id):
		return -1
	var item = balance.site_building(site_buildings.get(site_id, "pad"))
	return item.kind if item != null else SiteBuildingData.Kind.LAUNCH_PAD

func site_building_of(site_id: String) -> SiteBuildingData:
	return balance.site_building(site_buildings.get(site_id, "pad")) if built_sites.has(site_id) else null

## Product of all income buildings (×1.5 each).
func income_multiplier() -> float:
	var result = 1.0
	for id in built_sites:
		var item = site_building_of(id)
		if item != null and item.kind == SiteBuildingData.Kind.INCOME:
			result *= item.income_multiplier
	return result

func base_aa_multiplier() -> float:
	return float(base_aa_boost + 1)

func build_site(id: String) -> Dictionary:
	for site in layout.get("build_sites", []):
		if site.id == id:
			return site
	return {}

func route_length(path: Array) -> float:
	var length = 0.0
	for i in range(path.size() - 1):
		length += path[i].distance_to(path[i + 1])
	return length

## Frames the player can build (starting frames + frames of opened regions).
func available_frames() -> Array:
	var ids = Array(balance.starting_frames)
	if campaign != null:
		for i in range(campaign.regions.size()):
			if i <= region_index or region_unlocked(i):
				for item in campaign.regions[i].new_frames:
					if item != null and not ids.has(item.id):
						ids.append(item.id)
	return ids

func available_modules() -> Array:
	var ids = Array(balance.starting_available)
	if campaign != null:
		for i in range(campaign.regions.size()):
			if i <= region_index or region_unlocked(i):
				for module in campaign.regions[i].new_modules:
					if module != null and not ids.has(module.id):
						ids.append(module.id)
	return ids

# ================================================================ adaptation effects

func counter_by_id(id: String) -> CounterData:
	if balance.route_counter != null and balance.route_counter.id == id:
		return balance.route_counter
	for module in balance.modules:
		if module != null and module.counter != null and module.counter.id == id:
			return module.counter
	return null

func _strength(index: int) -> float:
	return 1.0 + (region_data.adaptation_escalation if region_data else 0.25) * index

func _mult(base_value: float, index: int) -> float:
	return 1.0 + (base_value - 1.0) * _strength(index)

## Effective parameters of an air-defense site after adaptations.
func aa_profile(id: String) -> Dictionary:
	var data: AirDefenseData = target_data(id).air_defense
	var profile = {"kind": data.kind_name(), "radius": data.radius, "accuracy": data.accuracy, "damage": data.damage * (region_data.aa_damage_multiplier if region_data else 1.0), "interval": data.interval, "capacity": data.targets_per_volley, "los": data.needs_line_of_sight, "jam_speed": data.jam_speed, "jam_accuracy": data.jam_accuracy}
	for i in range(adaptations.size()):
		var counter = counter_by_id(adaptations[i])
		if counter == null or counter.deploys_reserve_site:
			continue
		if not counter.affects.is_empty() and not counter.affects.has(profile.kind):
			continue
		profile.accuracy *= _mult(counter.accuracy_multiplier, i)
		profile.damage *= _mult(counter.damage_multiplier, i)
		profile.interval *= _mult(counter.interval_multiplier, i)
		profile.radius *= _mult(counter.radius_multiplier, i)
		profile.capacity += counter.capacity_bonus
	return profile

func target_armor(id: String) -> float:
	var item = target(id)
	var armor = item.get("armor", 0.0)
	var data = target_data(id)
	if data != null and data.is_main_target:
		for i in range(adaptations.size()):
			var counter = counter_by_id(adaptations[i])
			if counter != null:
				armor += counter.main_target_armor_bonus * _strength(i)
	return armor

# ================================================================ techs

func tech_mods() -> Dictionary:
	var mods = {"drone_damage": 1.0, "drone_hp": 1.0, "drone_speed": 1.0, "drone_cost": 1.0, "build_time": 1.0, "income": 1.0, "hunter_steal": 1.0, "base_defense_damage": 1.0, "extra_agility": 0.0, "extra_range": 0.0, "extra_reserve_protection": 0}
	if campaign == null:
		return mods
	for tech in campaign.techs:
		if tech == null or not techs.has(tech.id):
			continue
		for key in ["drone_damage", "drone_hp", "drone_speed", "drone_cost", "build_time", "income", "hunter_steal", "base_defense_damage"]:
			mods[key] *= tech.get(key)
		mods.extra_agility += tech.extra_agility
		mods.extra_range += tech.extra_range
		mods.extra_reserve_protection += tech.extra_reserve_protection
	return mods

func tech_available(tech: TechData) -> bool:
	if techs.has(tech.id):
		return false
	for requirement in tech.requires:
		if requirement != null and not techs.has(requirement.id):
			return false
	return true

func buy_tech(id: String) -> bool:
	for tech in campaign.techs:
		if tech != null and tech.id == id and tech_available(tech) and tech_points >= tech.cost:
			tech_points -= tech.cost
			techs.append(id)
			notice.emit("Technology acquired: %s" % tech.display_name)
			return true
	return false

# ================================================================ player actions

func _line(id: int, title: String, build: Dictionary, route_id: int, free: bool = false) -> Dictionary:
	return {"id": id, "name": title, "build": build.duplicate(true), "route": route_id, "free": free, "enabled": free, "order": {}, "disabled": 0.0, "income": 0.0, "spent": 0.0, "launched": 0, "hit": 0, "lost": 0, "miss": 0, "lost_by": {}, "level": 0}

## Price of the next UPGRADE of a line (200, 400, 600…).
func line_upgrade_price(item: Dictionary) -> int:
	return balance.line_upgrade_price_step * (int(item.get("level", 0)) + 1)

func upgrade_line(id: int) -> bool:
	var item = line(id)
	if item.is_empty() or item.free:
		return false
	var price = line_upgrade_price(item)
	if credits < price:
		notice.emit("Not enough credits: the upgrade costs %d cr." % price)
		return false
	credits -= price
	totals.spent += price
	item.level = int(item.get("level", 0)) + 1
	notice.emit("%s upgraded to level %d: all drone stats +%d%%." % [item.name, item.level, roundi(balance.line_upgrade_bonus * 100 * item.level)])
	return true

func paid_line_count() -> int:
	return lines.size() - 1

func next_slot_price() -> int:
	return balance.line_slot_prices[line_slots] if line_slots < balance.line_slot_prices.size() else -1

func buy_line_slot() -> bool:
	var price = next_slot_price()
	if price < 0 or credits < price:
		notice.emit("Not enough credits for a new line slot." if price >= 0 else "All line slots are open.")
		return false
	credits -= price
	line_slots += 1
	notice.emit("New assembly line slot opened.")
	return true

func add_route(points: Array, target_id: String, replace_id: int = -1) -> int:
	if points.size() < 2 or target(target_id).is_empty() or not target(target_id).active:
		return -1
	var start: Vector2 = points[0]
	var origin = base_position
	for point in launch_points():
		if point.distance_to(start) < start.distance_to(origin):
			origin = point
	var path: Array = [origin]
	for i in range(1, points.size() - 1):
		var point: Vector2 = points[i]
		if point.x < 0 or point.y < 0 or point.x > MAP_SIZE.x or point.y > MAP_SIZE.y:
			return -1
		if point.distance_to(path.back()) > 1.2:
			path.append(point)
	path.append(target(target_id).position)
	if replace_id >= 0 and not route(replace_id).is_empty():
		var existing = route(replace_id)
		existing.points = path
		existing.target = target_id
		return replace_id
	if routes.size() >= balance.max_routes:
		notice.emit("Route limit reached (%d). Delete an unused arrow." % balance.max_routes)
		return -1
	var id = next_route
	next_route += 1
	routes.append({"id": id, "points": path, "target": target_id})
	return id

func delete_route(id: int) -> void:
	for item in lines:
		if item.route == id:
			item.route = -1
	for i in range(routes.size() - 1, -1, -1):
		if routes[i].id == id:
			routes.remove_at(i)
	notice.emit("Route deleted. Drones already in the air keep their path.")

func assign(line_id: int, route_id: int) -> bool:
	var item = line(line_id)
	if item.is_empty() or route(route_id).is_empty():
		return false
	item.route = route_id
	var length = route_length(route(route_id).points)
	var reach = line_stats(item).range
	if length > reach:
		notice.emit("%s cannot reach this target: route %.0f km, range %.0f km. Add a fuel tank or launch from a forward pad." % [item.name, length, reach])
	else:
		notice.emit("%s assigned to route R%d. Press PLAY if the line is stopped." % [item.name, route_id])
	return true

func create_line(title: String, build: Dictionary) -> int:
	if paid_line_count() >= line_slots or not balance.build_error(build, unlocked, frame_level, available_frames()).is_empty():
		return -1
	var id = next_line
	next_line += 1
	lines.append(_line(id, title.strip_edges().left(28) if not title.strip_edges().is_empty() else "Line %d" % id, build, -1))
	notice.emit("Line created. Drag it onto a route arrow on the map.")
	return id

func update_build(id: int, title: String, build: Dictionary) -> bool:
	var item = line(id)
	if item.is_empty() or item.free or not balance.build_error(build, unlocked, frame_level, available_frames()).is_empty():
		return false
	item.build = build.duplicate(true)
	item.name = title.strip_edges().left(28) if not title.strip_edges().is_empty() else item.name
	return true

func unlock(id: String) -> bool:
	var module = balance.module(id)
	if module == null or unlocked.has(id) or not available_modules().has(id):
		return false
	var price = module.unlock_cost
	if credits < price:
		notice.emit("Not enough credits to unlock this module.")
		return false
	credits -= price
	unlocked.append(id)
	notice.emit("Module unlocked: %s" % module.display_name)
	return true

func upgrade_price(kind: String) -> int:
	var prices = balance.frame_upgrade_prices if kind == "frame" else balance.factory_upgrade_prices
	var level = frame_level if kind == "frame" else factory_level
	if kind == "base_defense":
		var levels = balance.base_defense_levels
		if base_defense_level <= 0:
			return levels[0].price if not levels.is_empty() else -1
		return balance.base_aa_upgrade_prices[base_aa_boost] if base_aa_boost < balance.base_aa_upgrade_prices.size() else -1
	return prices[level] if level < prices.size() else -1

func upgrade(kind: String) -> bool:
	var price = upgrade_price(kind)
	if price < 0 or credits < price:
		return false
	credits -= price
	match kind:
		"frame":
			frame_level += 1
			notice.emit("Airframes upgraded: +%d utility slot and +%d mass on every frame." % [frame_level, frame_level * balance.frame_mass_per_upgrade])
		"factory":
			factory_level += 1
			notice.emit("Assembly upgraded to level %d." % factory_level)
		"base_defense":
			if base_defense_level <= 0:
				base_defense_level = 1
				notice.emit("Base air defense online. It cripples and slows hunters near the base.")
			else:
				base_aa_boost += 1
				notice.emit("Air defense upgraded: damage ×%d." % (base_aa_boost + 1))
	return true

func building_price(site_id: String, building_id: String) -> int:
	var site = build_site(site_id)
	var item = balance.site_building(building_id)
	if site.is_empty() or item == null:
		return -1
	return int(round(site.price * item.price_multiplier))

## Builds one of balance.site_buildings on an empty build site.
func build_pad(id: String, building_id: String = "pad") -> bool:
	var site = build_site(id)
	var item = balance.site_building(building_id)
	if site.is_empty() or built_sites.has(id) or item == null:
		notice.emit("Already built." if built_sites.has(id) else "Cannot build here.")
		return false
	var price = building_price(id, building_id)
	if credits < price:
		notice.emit("Not enough credits: %s costs %d cr." % [item.display_name, price])
		return false
	credits -= price
	totals.spent += price
	built_sites.append(id)
	site_buildings[id] = building_id
	match item.kind:
		SiteBuildingData.Kind.LAUNCH_PAD:
			notice.emit("Forward launch pad built. Draw routes starting from it.")
		SiteBuildingData.Kind.AIR_DEFENSE:
			notice.emit("Air-defense tower built. It shoots down hunters flying past.")
		SiteBuildingData.Kind.INCOME:
			notice.emit("%s built: all income ×%s." % [item.display_name, str(snappedf(income_multiplier(), 0.01))])
	return true

func activate_overdrive() -> bool:
	if overdrive_cooldown > 0 or victory:
		return false
	overdrive = balance.boost_duration
	overdrive_cooldown = balance.boost_cooldown
	notice.emit("Boost active for %d s. Paid lines spend credits faster." % int(balance.boost_duration))
	return true

func line_stats(item: Dictionary) -> Dictionary:
	var mods = tech_mods()
	if item.free:
		return balance.free_stats(mods)
	var result = balance.stats(item.build, frame_level, factory_level, mods)
	var bonus = 1.0 + balance.line_upgrade_bonus * int(item.get("level", 0))
	for key in ["damage", "hp", "speed", "agility", "penetration", "range"]:
		result[key] = float(result[key]) * bonus
	return result

func status(item: Dictionary) -> String:
	if item.get("disabled", 0.0) > 0:
		return "Disabled by hunters · %ds" % ceili(item.disabled)
	if not item.order.is_empty():
		if item.order.remaining <= 0:
			return "Drone ready · waiting for route / start"
		return "Building · %.1fs" % item.order.remaining
	if not item.enabled:
		return "Paused"
	var path = route(item.route)
	if path.is_empty():
		return "Assign a route"
	if route_length(path.points) > line_stats(item).range:
		return "Out of range · %.0f / %.0f km" % [route_length(path.points), line_stats(item).range]
	if target(path.target).hp <= 0:
		return "Target down · waiting for repair"
	if drones.size() >= balance.max_drones:
		return "Airspace full · waiting"
	if credits - line_stats(item).cost < reserve and not item.free:
		return "Waiting for credits · reserve %d" % reserve
	return "Ready"

## Short player-facing status for a line: {text, hint, level} where level is
## "ok" (working), "warn" (waiting, will resolve itself) or "bad" (needs the player).
func status_info(item: Dictionary) -> Dictionary:
	if item.get("disabled", 0.0) > 0:
		return {"text": "HIT BY HUNTERS · %ds" % ceili(item.disabled), "hint": "Hunters reached your base and knocked this line out. It restarts by itself. Tap hunters before they arrive.", "level": "bad"}
	if not item.enabled:
		return {"text": "PAUSED · press START", "hint": "The line is paused. Press the start button to resume production.", "level": "warn"}
	var path = route(item.route)
	if path.is_empty():
		return {"text": "NO ROUTE · drag onto an arrow", "hint": "Drag this row onto a route arrow on the map (or draw a route from your base first).", "level": "bad"}
	var stats = line_stats(item)
	if route_length(path.points) > stats.range:
		return {"text": "OUT OF RANGE · %d/%d km" % [int(route_length(path.points)), int(stats.range)], "hint": "The route is longer than the drone can fly. Add a fuel tank, draw a shorter route or build a forward pad.", "level": "bad"}
	if target(path.target).hp <= 0:
		return {"text": "TARGET DOWN · waiting", "hint": "The target is destroyed and being rebuilt. Point the line at another target meanwhile.", "level": "warn"}
	var lost = int(item.get("lost", 0))
	var hit = int(item.get("hit", 0))
	if not item.free and lost >= 5 and hit * 2 < lost:
		return {"text": "HEAVY LOSSES · see intel", "hint": "Most drones are shot down. Click the line to see what kills them and change the build or route.", "level": "bad"}
	if not item.order.is_empty() and item.order.remaining > 0:
		return {"text": "BUILDING · %.1fs" % item.order.remaining, "hint": "A drone is being assembled. It launches as soon as it is ready.", "level": "ok"}
	if drones.size() >= balance.max_drones:
		return {"text": "AIRSPACE FULL · waiting", "hint": "Too many drones in the air. The line launches when some land or fall.", "level": "warn"}
	if not item.free and item.order.is_empty() and credits - stats.cost < reserve:
		return {"text": "NEED CREDITS · %d cr" % stats.cost, "hint": "Credits above the reserve (%d) are not enough for one drone (%d cr). Lower the reserve or wait for income." % [reserve, stats.cost], "level": "warn"}
	return {"text": "WORKING", "hint": "Building and launching drones along the route.", "level": "ok"}

## Player tapped a hunter. Returns true if it was hit.
func hit_hunter(id: int) -> bool:
	var hunter_data = _hunter_data()
	for hunter in hunters:
		if hunter.id == id and hunter.hp > 0:
			hunter.hp -= hunter_data.click_damage if hunter_data else 12.0
			shot.emit(base_position, hunter.position, "tap", true)
			if hunter.hp <= 0:
				var bounty = float(hunter_data.tap_bounty if hunter_data else 10)
				credits += bounty
				totals.income += bounty
				totals.hunters_tapped = int(totals.get("hunters_tapped", 0)) + 1
				floater.emit("SHOT DOWN +%d" % int(bounty), hunter.position, "income")
			return true
	return false

# ================================================================ simulation step

func step(delta: float) -> void:
	if victory:
		return
	elapsed += delta
	overdrive = maxf(0, overdrive - delta)
	overdrive_cooldown = maxf(0, overdrive_cooldown - delta)
	adaptation_lock = maxf(0, adaptation_lock - delta)
	_tick_targets(delta)
	_tick_adaptation(delta)
	for item in lines:
		_tick_line(item, delta)
	_tick_air_defense(delta)
	_tick_hunters(delta)
	_move_drones(delta)

func _tick_targets(delta: float) -> void:
	for item in targets:
		if not item.active:
			continue
		item.since_hit += delta
		if item.respawn > 0:
			item.respawn = maxf(0, item.respawn - delta)
			if item.respawn == 0:
				item.hp = item.max_hp
				notice.emit("%s repaired." % item.name)
			continue
		var data = target_data(item.id)
		if item.hp > 0 and data.regen_percent_per_second > 0 and item.since_hit >= data.regen_delay:
			item.hp = minf(item.max_hp, item.hp + item.max_hp * data.regen_percent_per_second / 100.0 * delta)

func _tick_line(item: Dictionary, delta: float) -> void:
	if item.get("disabled", 0.0) > 0:
		item.disabled = maxf(0, item.disabled - delta)
		if item.disabled == 0:
			notice.emit("%s is back online." % item.name)
		return
	var path = route(item.route)
	var valid = not path.is_empty() and target(path.target).hp > 0 and target(path.target).active
	if valid and route_length(path.points) > line_stats(item).range:
		valid = false
	if item.enabled and valid and item.order.is_empty() and drones.size() < balance.max_drones:
		var stats = line_stats(item)
		if item.free or credits - stats.cost >= reserve:
			credits -= stats.cost
			item.spent += stats.cost
			totals.spent += stats.cost
			item.order = {"stats": stats.duplicate(true), "build": item.build.duplicate(true), "remaining": stats.interval, "duration": stats.interval, "cost": stats.cost}
	if item.order.is_empty():
		return
	item.order.remaining = maxf(0, item.order.remaining - delta * (1.0 / balance.boost_time_multiplier if overdrive > 0 else 1.0))
	if item.order.remaining <= 0 and item.enabled and valid and drones.size() < balance.max_drones:
		var order = item.order
		drones.append({"id": next_drone, "line": item.id, "free": item.free, "stats": order.stats.duplicate(true), "build": order.build.duplicate(true), "path": path.points.duplicate(), "route": path.id, "target": path.target, "segment": 0, "position": path.points[0], "hp": order.stats.hp, "decoys": order.stats.get("decoys", 0), "jammed": false, "last_hit": ""})
		next_drone += 1
		effect.emit("launch", path.points[0])
		item.launched += 1
		totals.launched += 1
		item.order = {}

func _line_of_sight(from: Vector2, to: Vector2) -> bool:
	var height: Callable = layout.get("height", Callable())
	if not height.is_valid():
		return true
	var a = height.call(from) + 2.5
	var b = height.call(to) + balance.flight_altitude
	for k in range(1, 9):
		var t = k / 9.0
		if height.call(from.lerp(to, t)) > lerpf(a, b, t) + 0.3:
			return false
	return true

func _tick_air_defense(delta: float) -> void:
	var main = main_target()
	var focus: Vector2 = main.position if not main.is_empty() else base_position
	for site in air_defenses():
		var profile = aa_profile(site.id)
		if profile.kind == "jammer":
			continue
		site.gun_timer = maxf(0, site.gun_timer - delta)
		if site.gun_timer > 0:
			continue
		var candidates = []
		for drone in drones:
			if drone.hp <= 0 or drone.position.distance_to(site.position) > profile.radius:
				continue
			if profile.los and not _line_of_sight(site.position, drone.position):
				continue
			candidates.append(drone)
		if candidates.is_empty():
			continue
		candidates.sort_custom(func(a, b): return a.position.distance_squared_to(focus) < b.position.distance_squared_to(focus))
		site.gun_timer = profile.interval
		for k in range(mini(profile.capacity, candidates.size())):
			var drone = candidates[k]
			var accuracy = profile.accuracy * float(drone.stats.get("ew_accuracy", 1.0))
			var hit = rng.randf() < clampf(accuracy / (accuracy + drone.stats.agility), balance.aa_min_hit_chance, balance.aa_max_hit_chance)
			var lock = 1.0 + minf(float(drone.get("exposure", 0.0)) * balance.aa_lock_on_per_second, balance.aa_lock_on_max - 1.0)
			shot.emit(site.position, drone.position, profile.kind, hit)
			effect.emit("shot", drone.position)
			if not hit:
				continue
			if drone.decoys > 0:
				drone.decoys -= 1
				floater.emit("DECOY", drone.position, "miss")
				continue
			drone.hp -= profile.damage * lock
			drone.last_hit = profile.kind
			effect.emit("flak", drone.position)

func _jam_factor(drone: Dictionary) -> float:
	if drone.stats.get("ew", false):
		return 1.0
	var factor = 1.0
	for site in air_defenses():
		var profile = aa_profile(site.id)
		if profile.kind == "jammer" and drone.position.distance_to(site.position) <= profile.radius:
			factor = minf(factor, profile.jam_speed)
			drone.jammed = true
			drone.jam_accuracy = profile.jam_accuracy
	return factor

## Seconds the drone has been inside air-defense rings (lock-on builds up, decays outside).
func _track_exposure(drone: Dictionary, delta: float) -> void:
	if drone.free:
		return
	var inside = false
	for site in air_defenses():
		var profile = aa_profile(site.id)
		if profile.kind != "jammer" and drone.position.distance_to(site.position) <= profile.radius:
			inside = true
			break
	drone.exposure = float(drone.get("exposure", 0.0)) + delta if inside else maxf(0.0, float(drone.get("exposure", 0.0)) - delta * 2.0)

func _move_drones(delta: float) -> void:
	for i in range(drones.size() - 1, -1, -1):
		var drone = drones[i]
		if drone.hp <= 0:
			_finish(drone, true)
			drones.remove_at(i)
			continue
		var distance = drone.stats.speed * delta * _jam_factor(drone)
		_track_exposure(drone, delta)
		while distance > 0 and drone.segment < drone.path.size() - 1:
			var destination: Vector2 = drone.path[drone.segment + 1]
			var remaining = drone.position.distance_to(destination)
			if remaining <= distance:
				drone.position = destination
				drone.segment += 1
				distance -= remaining
			else:
				drone.position = drone.position.move_toward(destination, distance)
				distance = 0
		var passed = _site_under(drone)
		if not passed.is_empty():
			drone.target = passed
			drone.segment = drone.path.size() - 1
		if drone.segment >= drone.path.size() - 1:
			var accuracy = float(drone.stats.get("accuracy", 1.0)) * (drone.get("jam_accuracy", 1.0) if drone.jammed else 1.0)
			if target(drone.target).hp > 0 and rng.randf() > accuracy:
				totals.miss += 1
				var source_line = line(drone.line)
				if not source_line.is_empty():
					source_line.miss += 1
				effect.emit("miss", target(drone.target).position)
				floater.emit("MISS", target(drone.target).position, "miss")
			else:
				_impact(drone)
			_finish(drone, false)
			drones.remove_at(i)
			if victory:
				drones.clear()
				break

## Enemy site the drone is flying over (it dives on the first building on its way).
func _site_under(drone: Dictionary) -> String:
	var radius = balance.flyover_hit_radius
	if radius <= 0 or drone.segment >= drone.path.size() - 1:
		return ""
	var start: Vector2 = drone.path[0]
	for item in targets:
		if not item.active or item.hp <= 0:
			continue
		var pos: Vector2 = item.position
		# Ignore sites right at the launch point (e.g. a captured site next to the base).
		if pos.distance_to(start) < radius * 2.0:
			continue
		if drone.position.distance_to(pos) <= radius:
			return item.id
	return ""

func _impact(drone: Dictionary) -> void:
	var obj = target(drone.target)
	if obj.is_empty() or obj.hp <= 0:
		return
	var data = target_data(obj.id)
	var armor = target_armor(obj.id) + float(drone.stats.get("armor_penalty", 0.0))
	var multiplier = float(drone.stats.get("anti_air", 1.0)) if data != null and (data.air_defense != null or data.counts_as_air_defense) else 1.0
	var damage = minf(obj.hp, drone.stats.damage * multiplier * 100.0 / (100.0 + balance.armor_weight * maxf(0, armor - drone.stats.penetration)))
	obj.hp -= damage
	obj.since_hit = 0.0
	var income = damage * obj.rate * tech_mods().income * income_multiplier()
	credits += income
	totals.income += income
	totals.hit += 1
	var source = line(drone.line)
	if not source.is_empty():
		source.income += income
		source.hit += 1
	effect.emit("hit", obj.position)
	floater.emit("+%d" % roundi(income), obj.position, "income")
	if obj.hp <= 0:
		if data != null and data.is_main_target:
			_win()
		else:
			obj.respawn = maxf(0.1, data.respawn_time if data != null else 15.0)
			notice.emit("%s destroyed. Back online in %ds." % [obj.name, int(obj.respawn)])

func _finish(drone: Dictionary, lost: bool) -> void:
	var source = line(drone.line)
	if lost:
		totals.lost += 1
		if not drone.free:
			run_losses += 1
		if not source.is_empty():
			source.lost += 1
			var reason = drone.last_hit if not drone.last_hit.is_empty() else "unknown"
			source.lost_by[reason] = int(source.lost_by.get(reason, 0)) + 1
		effect.emit("lost", drone.position)
		floater.emit("DOWN", drone.position, "lost")
	var data = target_data(drone.target)
	if not drone.free and data != null and data.is_main_target and not victory:
		observations.append({"modules": drone.build.get("modules", []).duplicate(), "route": drone.route, "lost": lost})
		if observations.size() > balance.adaptation_window:
			observations.pop_front()

# ================================================================ adaptation

func adaptation_budget() -> int:
	return region_data.adaptation_budget if region_data else 2

func _tick_adaptation(delta: float) -> void:
	if not pending_adaptation.is_empty():
		adaptation_timer -= delta
		if adaptation_timer <= 0:
			var counter = counter_by_id(pending_adaptation)
			if counter != null and counter.deploys_reserve_site and not pending_reserve.is_empty():
				var site = target(pending_reserve)
				site.active = true
				site.hp = site.max_hp
				effect.emit("deploy", site.position)
			adaptations.append(pending_adaptation)
			pending_adaptation = ""
			pending_reserve = ""
			adaptation_lock = balance.adaptation_lock
			observations.clear()
			notice.emit("Air defense adapted: %s" % (counter.display_name if counter else "?"))
		return
	if adaptations.size() >= adaptation_budget() or adaptation_lock > 0 or observations.size() < balance.adaptation_window:
		return
	# Module-based responses.
	var best = ""
	var best_count = balance.adaptation_threshold - 1
	for id in balance.module_ids():
		var counter = balance.counter(id)
		if counter == null or adaptations.has(counter.id):
			continue
		var count = observations.filter(func(o): return o.modules.has(id)).size()
		if count > best_count:
			best = counter.id
			best_count = count
	# Route-based response: everyone uses one route and survives.
	var route_counter = balance.route_counter
	if route_counter != null:
		var counts = {}
		for o in observations:
			counts[o.route] = int(counts.get(o.route, 0)) + 1
		for route_id in counts:
			var share = float(counts[route_id]) / observations.size()
			var survived = observations.filter(func(o): return o.route == route_id and not o.lost).size()
			if share >= balance.route_adaptation_share and survived >= counts[route_id] * 0.6:
				var reserve_site = _closest_reserve(route(route_id))
				if not reserve_site.is_empty() and (best.is_empty() or counts[route_id] >= best_count):
					best = route_counter.id
					pending_reserve = reserve_site.id
	if not best.is_empty():
		pending_adaptation = best
		adaptation_timer = balance.adaptation_warning
		var counter = counter_by_id(best)
		notice.emit("Air defense adapting in %ds: %s. %s" % [int(balance.adaptation_warning), counter.display_name, counter.description])

func _closest_reserve(path: Dictionary) -> Dictionary:
	if path.is_empty():
		return {}
	var best = {}
	var best_distance = INF
	for item in targets:
		if item.active or not item.reserve:
			continue
		for p in path.points:
			var d = p.distance_to(item.position)
			if d < best_distance:
				best_distance = d
				best = item
	return best

# ================================================================ hunters & base defense

func _tick_hunters(delta: float) -> void:
	var data = _hunter_data()
	if data != null and data.enabled and hunter_timer >= 0:
		hunter_timer -= delta
		if hunter_timer <= 0:
			hunter_timer = data.wave_interval + rng.randf_range(-data.wave_interval_jitter, data.wave_interval_jitter)
			var origin = main_target()
			var start: Vector2 = origin.position if not origin.is_empty() else Vector2(MAP_SIZE.x, 0)
			for k in range(data.drones_per_wave):
				var from = start + Vector2(rng.randf_range(-3, 3), rng.randf_range(-3, 3))
				var span = base_position - from
				var bend = span.orthogonal() * data.curve_strength * rng.randf_range(-1.0, 1.0)
				hunters.append({"id": next_drone, "position": from, "from": from, "ctrl": from.lerp(base_position, rng.randf_range(0.35, 0.65)) + bend, "t": 0.0, "phase": rng.randf() * TAU, "heading": span.normalized(), "hp": data.hp, "max_hp": data.hp, "slowed": false})
				next_drone += 1
			notice.emit(data.warning_text)
			effect.emit("hunters", start)
	# Base air defense.
	base_gun_timer = maxf(0, base_gun_timer - delta)
	var defense = _base_defense()
	if defense != null and base_gun_timer <= 0:
		var nearest = {}
		var best = defense.radius
		for hunter in hunters:
			var d = hunter.position.distance_to(base_position)
			var floor_hp = hunter.max_hp * defense.min_hp_fraction
			if hunter.hp > floor_hp + 0.01 and d <= best:
				best = d
				nearest = hunter
		if not nearest.is_empty():
			base_gun_timer = defense.interval
			var floor_hp = nearest.max_hp * defense.min_hp_fraction
			nearest.hp = maxf(floor_hp, nearest.hp - defense.damage * tech_mods().base_defense_damage * base_aa_multiplier())
			shot.emit(base_position, nearest.position, "gun", true)
			effect.emit("flak", nearest.position)
			if nearest.hp <= 0:
				floater.emit("SHOT DOWN", nearest.position, "income")
			elif nearest.hp <= floor_hp + 0.01:
				floater.emit("CRIPPLED · TAP!", nearest.position, "miss")
	_tick_site_towers(delta)
	for i in range(hunters.size() - 1, -1, -1):
		var hunter = hunters[i]
		if hunter.hp <= 0:
			effect.emit("lost", hunter.position)
			hunters.remove_at(i)
			continue
		var speed = data.speed if data else 11.0
		hunter.slowed = defense != null and hunter.position.distance_to(base_position) <= defense.radius
		if hunter.slowed:
			speed *= defense.slow_factor
		var before: Vector2 = hunter.position
		if hunter.has("from"):
			var from: Vector2 = hunter.from
			var ctrl: Vector2 = hunter.ctrl
			var length = maxf(1.0, from.distance_to(ctrl) + ctrl.distance_to(base_position))
			hunter.t = minf(1.0, float(hunter.t) + speed * delta / length)
			var t = float(hunter.t)
			var p = from.lerp(ctrl, t).lerp(ctrl.lerp(base_position, t), t)
			var tangent = (ctrl - from).lerp(base_position - ctrl, t).normalized()
			# Weave fades out near the base so the hunter still lands on it.
			var weave = sin(t * TAU * (data.weave_count if data else 3.0) + float(hunter.phase)) * (data.weave_amplitude if data else 3.0) * (1.0 - t)
			hunter.position = p + tangent.orthogonal() * weave
			if t >= 1.0:
				hunter.position = base_position
		else:
			hunter.position = hunter.position.move_toward(base_position, speed * delta)
		if hunter.position.distance_to(before) > 0.001:
			hunter.heading = (hunter.position - before).normalized()
		if hunter.position.distance_to(base_position) < 1.0:
			_hunter_strike(data)
			hunters.remove_at(i)

## Air-defense towers on build sites: they shoot hunters down completely.
func _tick_site_towers(delta: float) -> void:
	for id in built_sites:
		var item = site_building_of(id)
		if item == null or item.kind != SiteBuildingData.Kind.AIR_DEFENSE:
			continue
		var timer = float(site_gun_timers.get(id, 0.0)) - delta
		if timer > 0:
			site_gun_timers[id] = timer
			continue
		var pos: Vector2 = build_site(id).position
		var nearest = {}
		var best = item.radius
		for hunter in hunters:
			var d = hunter.position.distance_to(pos)
			if hunter.hp > 0 and d <= best:
				best = d
				nearest = hunter
		if nearest.is_empty():
			site_gun_timers[id] = 0.0
			continue
		site_gun_timers[id] = item.interval
		nearest.hp -= item.damage * tech_mods().base_defense_damage * base_aa_multiplier()
		shot.emit(pos, nearest.position, "gun", true)
		effect.emit("flak", nearest.position)
		if nearest.hp <= 0:
			floater.emit("SHOT DOWN", nearest.position, "income")

func _base_defense() -> BaseDefenseData:
	if base_defense_level <= 0 or balance.base_defense_levels.is_empty():
		return null
	return balance.base_defense_levels[mini(base_defense_level, balance.base_defense_levels.size()) - 1]

func _hunter_strike(data: HunterData) -> void:
	var protected = float(tech_mods().extra_reserve_protection)
	var stolen = maxf(0.0, credits - protected) * (data.steal_fraction if data else 0.3) * tech_mods().hunter_steal
	credits -= stolen
	totals.stolen += stolen
	totals.strikes = int(totals.get("strikes", 0)) + 1
	effect.emit("hit", base_position)
	floater.emit("-%d" % roundi(stolen), base_position, "lost")
	var candidates = lines.filter(func(l): return l.enabled and l.get("disabled", 0.0) <= 0 and not l.free)
	if candidates.is_empty():
		candidates = lines.filter(func(l): return l.get("disabled", 0.0) <= 0)
	var hit_line = ""
	if not candidates.is_empty():
		var item = candidates[rng.randi_range(0, candidates.size() - 1)]
		item.disabled = data.disable_seconds if data else 25.0
		item.order = {}
		hit_line = item.name
	notice.emit("Hunters hit the base: -%d cr%s." % [roundi(stolen), (", %s disabled for %ds" % [hit_line, int(data.disable_seconds if data else 25.0)]) if not hit_line.is_empty() else ""])

# ================================================================ victory & stars

func _win() -> void:
	victory = true
	for item in lines:
		if not item.order.is_empty():
			credits += item.order.cost
			item.spent -= item.order.cost
			totals.spent -= item.order.cost
			item.order = {}
	var id = region_data.id if region_data else "region"
	var state = region_states.get(id, {"stars": 0, "cleared": false, "best_time": 0.0})
	var stars = 1
	var time_ok = region_data == null or elapsed <= region_data.star_time
	var losses_ok = region_data == null or run_losses <= region_data.star_max_losses
	stars += int(time_ok) + int(losses_ok)
	var new_stars = maxi(0, stars - int(state.stars))
	var points = new_stars * (campaign.tech_points_per_star if campaign else 1)
	tech_points += points
	var reward = region_data.capture_reward if region_data else 400
	if state.cleared:
		reward = int(reward * 0.25)
	credits += reward
	state.stars = maxi(int(state.stars), stars)
	state.cleared = true
	state.best_time = elapsed if state.best_time <= 0 else minf(state.best_time, elapsed)
	region_states[id] = state
	result = {"region": id, "stars": stars, "time": elapsed, "time_ok": time_ok, "time_limit": region_data.star_time if region_data else 0.0, "losses": run_losses, "losses_ok": losses_ok, "loss_limit": region_data.star_max_losses if region_data else 0, "reward": reward, "tech_points": points, "first_clear": reward == (region_data.capture_reward if region_data else 400)}
	notice.emit("Region captured! +%d cr, +%d tech points." % [reward, points])
	region_finished.emit(result)

# ================================================================ saving

const PERSISTENT_KEYS = ["credits", "reserve", "frame_level", "factory_level", "line_slots", "base_defense_level", "base_aa_boost", "unlocked", "lines", "next_line", "techs", "tech_points", "region_index", "region_states", "totals"]
const RUN_KEYS = ["targets", "routes", "drones", "hunters", "built_sites", "site_buildings", "next_route", "next_drone", "elapsed", "run_losses", "overdrive", "overdrive_cooldown", "victory", "result", "adaptations", "pending_adaptation", "pending_reserve", "adaptation_timer", "adaptation_lock", "observations", "hunter_timer", "base_gun_timer"]

func snapshot() -> Dictionary:
	var data = {"version": VERSION, "rng_state": str(rng.state)}
	for key in PERSISTENT_KEYS + RUN_KEYS:
		data[key] = get(key)
	return _pack(data)

func _pack(value: Variant) -> Variant:
	if value is Vector2:
		return {"$v2": [value.x, value.y]}
	if value is Dictionary:
		var packed = {}
		for key in value:
			packed[key] = _pack(value[key])
		return packed
	if value is Array:
		return value.map(func(v): return _pack(v))
	return value

func _unpack(value: Variant) -> Variant:
	if value is Dictionary:
		if value.has("$v2"):
			return Vector2(value["$v2"][0], value["$v2"][1])
		var unpacked = {}
		for key in value:
			unpacked[key] = _unpack(value[key])
		return unpacked
	if value is Array:
		return value.map(func(v): return _unpack(v))
	return value

## Reads the saved region index without applying the save (to load the right scene first).
static func peek_region(path: String = SAVE_PATH) -> int:
	if not FileAccess.file_exists(path):
		return -1
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	return int(data.get("region_index", 0)) if data is Dictionary and int(data.get("version", 0)) == VERSION else -1

## Restores progress; the region layout must already be set via start_region().
func restore(data: Dictionary) -> bool:
	if int(data.get("version", 0)) != VERSION:
		return false
	var decoded = _unpack(data)
	for key in PERSISTENT_KEYS + RUN_KEYS:
		if decoded.has(key):
			set(key, decoded[key])
	for key in ["line_slots", "frame_level", "factory_level", "base_defense_level", "base_aa_boost", "next_line", "tech_points", "region_index", "next_route", "next_drone", "run_losses"]:
		set(key, int(get(key)))
	base_defense_level = mini(base_defense_level, 1)
	rng.state = int(data.rng_state)
	_sync_layout()
	return true

## Keep saved HP/timers but take positions, names and the target list from the current scene.
func _sync_layout() -> void:
	var saved = {}
	for item in targets:
		saved[item.id] = item
	_setup_targets()
	for item in targets:
		if saved.has(item.id):
			var old = saved[item.id]
			item.hp = item.max_hp * clampf(old.hp / maxf(1.0, old.max_hp), 0.0, 1.0)
			item.respawn = old.get("respawn", 0.0)
			item.active = old.get("active", item.active)
	# A region's authored sites can change between saves (e.g. a removed battery).
	# Discard references to missing objectives rather than leaving drones/UI to
	# access an empty target. Paid orders stay on their lines awaiting a new route.
	routes = routes.filter(func(path): return not target(path.target).is_empty())
	drones = drones.filter(func(drone): return not target(drone.target).is_empty())
	for item in lines:
		if route(item.route).is_empty():
			item.route = -1
	if not pending_reserve.is_empty() and target(pending_reserve).is_empty():
		pending_reserve = ""
		pending_adaptation = ""
		adaptation_timer = 0.0

func save_game(path: String = SAVE_PATH) -> bool:
	var file = FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(snapshot()))
	file.flush()
	file.close()
	return DirAccess.rename_absolute(path + ".tmp", path) == OK

func load_game(path: String = SAVE_PATH) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	return data is Dictionary and restore(data)
