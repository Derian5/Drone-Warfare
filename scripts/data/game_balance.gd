@tool
class_name GameBalance
extends Resource
## Global rules (data/balance.tres). Region-specific rules live in RegionData.

@export_group("Economy")
@export var starting_credits := 500.0
@export var starting_reserve := 100
## Price of each modular line slot. First entry = first slot (0 = free).
@export var line_slot_prices: PackedInt32Array = [0, 150, 300]

@export_group("Limits")
@export var max_routes := 8
@export var max_drones := 100
@export var free_line_target := "depot"

@export_group("Modular drones")
## Frames (airframes). Base stats live in each FrameData (data/frames/*.tres).
@export var frames: Array[FrameData] = []
## Frames available from the start; others come with regions (RegionData.new_frames).
@export var starting_frames: PackedStringArray = ["quad"]
## Base damage before the warhead and frame bonus.
@export var frame_damage := 30.0
@export var frame_penetration := 0.0
@export var min_speed := 6.0
## Price of each airframe upgrade level. Every level (all frames): +1 slot, +mass, +cost per drone.
@export var frame_upgrade_prices: PackedInt32Array = [225, 450]
@export var frame_mass_per_upgrade := 4
@export var frame_cost_per_upgrade := 4
## Price of each assembly upgrade level. Every level multiplies build time.
@export var factory_upgrade_prices: PackedInt32Array = [275, 420, 640]
@export_range(0.1, 1) var factory_time_multiplier := 0.85

@export_group("Free drone")
@export var free_damage := 14.0
@export var free_hp := 14.0
@export var free_speed := 14.0
@export var free_agility := 12.0
@export_range(0, 1) var free_accuracy := 0.9
@export var free_build_time := 4.5
@export var free_range := 999.0

@export_group("Air defense")
@export_range(0, 1) var aa_min_hit_chance := 0.10
@export_range(0, 1) var aa_max_hit_chance := 0.95
## Altitude used for radar line-of-sight checks.
@export var flight_altitude := 3.4

@export_group("Base defense")
@export var base_defense_levels: Array[BaseDefenseData] = []

@export_group("Boost")
@export var boost_duration := 10.0
@export var boost_cooldown := 45.0
@export_range(0.1, 1) var boost_time_multiplier := 0.75

@export_group("Adaptation")
@export var adaptation_window := 12
@export var adaptation_threshold := 8
@export var adaptation_warning := 15.0
@export var adaptation_lock := 45.0
## Share of the window's HQ attackers that must use one route to trigger a route response.
@export_range(0.3, 1.0) var route_adaptation_share := 0.75

@export_group("Content")
@export var modules: Array[ModuleData] = []
@export var route_counter: CounterData
@export var starting_unlocked: PackedStringArray = ["fragment", "armor"]
## Modules available for research from the start (others come with regions).
@export var starting_available: PackedStringArray = ["fragment", "piercing", "armor", "maneuver", "boost", "payload"]
@export var default_build_warhead := "fragment"
@export var default_build_modules: PackedStringArray = ["armor"]
@export var route_colors: PackedColorArray = [Color("38d5df"), Color("ae92ff"), Color("ffd270"), Color("ff8daf"), Color("8dda8b")]

# ---------------------------------------------------------------- queries

func module(id: String) -> ModuleData:
	for item in modules:
		if item != null and item.id == id:
			return item
	return null

func module_ids() -> Array:
	return modules.filter(func(m): return m != null).map(func(m): return m.id)

func counter(id: String) -> CounterData:
	var source = module(id)
	return source.counter if source != null else null

func frame(id: String) -> FrameData:
	for item in frames:
		if item != null and item.id == id:
			return item
	return frames[0] if not frames.is_empty() else null

## Frame id of a build (old builds without a frame use the first frame).
func build_frame(build: Dictionary) -> String:
	var item = frame(str(build.get("frame", "")))
	return item.id if item != null else ""

func slots(frame_level: int, frame_id: String = "") -> int:
	var item = frame(frame_id)
	return (item.slots if item != null else 2) + frame_level

func max_mass(frame_level: int, frame_id: String = "") -> int:
	var item = frame(frame_id)
	return (item.max_mass if item != null else 8) + frame_level * frame_mass_per_upgrade

## Can this module be installed on this frame?
func fits(module_id: String, frame_id: String) -> bool:
	var item = module(module_id)
	return item != null and (item.frames.is_empty() or item.frames.has(frame_id))

func route_color(id: int) -> Color:
	return route_colors[(id - 1) % route_colors.size()] if not route_colors.is_empty() else Color.CYAN

## mods: tech multipliers from Simulation.tech_mods().
func stats(build: Dictionary, frame_level: int = 0, factory_level: int = 0, mods: Dictionary = {}) -> Dictionary:
	var f = frame(str(build.get("frame", "")))
	var result = {"damage": frame_damage + f.damage_bonus, "hp": f.hp, "speed": f.speed, "agility": f.agility, "penetration": frame_penetration, "accuracy": f.accuracy, "range": f.flight_range, "decoys": 0, "ew": false, "ew_accuracy": 1.0, "anti_air": 1.0, "armor_penalty": 0.0, "mass": 0, "cost": f.cost + frame_level * frame_cost_per_upgrade, "interval": f.build_time * pow(factory_time_multiplier, factory_level), "frame": f.id}
	var ids = [build.get("warhead", default_build_warhead)]
	ids.append_array(build.get("modules", []))
	for id in ids:
		var item = module(id)
		if item == null:
			continue
		result.damage += item.damage
		result.hp += item.hp
		result.speed += item.speed
		result.agility += item.agility
		result.penetration += item.penetration
		result.range += item.flight_range
		result.decoys += item.decoys
		result.mass += item.mass
		result.cost += item.cost_per_drone
		result.armor_penalty += item.armor_penalty
		result.accuracy = clampf(result.accuracy + item.accuracy, 0.05, 1.0)
		result.ew_accuracy *= item.enemy_accuracy
		result.anti_air *= item.anti_air_multiplier
		if item.ew_pod:
			result.ew = true
			result.ew_accuracy = minf(result.ew_accuracy, item.ew_enemy_accuracy)
	_apply_mods(result, mods)
	result.speed = maxf(min_speed, result.speed)
	result.agility = maxf(0.0, result.agility)
	return result

func free_stats(mods: Dictionary = {}) -> Dictionary:
	var result = {"damage": free_damage, "hp": free_hp, "speed": free_speed, "agility": free_agility, "penetration": 0.0, "accuracy": free_accuracy, "range": free_range, "decoys": 0, "ew": false, "ew_accuracy": 1.0, "anti_air": 1.0, "armor_penalty": 0.0, "mass": 0, "cost": 0, "interval": free_build_time}
	_apply_mods(result, mods)
	return result

func _apply_mods(result: Dictionary, mods: Dictionary) -> void:
	if mods.is_empty():
		return
	result.damage *= mods.get("drone_damage", 1.0)
	result.hp *= mods.get("drone_hp", 1.0)
	result.speed *= mods.get("drone_speed", 1.0)
	result.cost = int(ceil(result.cost * mods.get("drone_cost", 1.0)))
	result.interval *= mods.get("build_time", 1.0)
	result.agility += mods.get("extra_agility", 0.0)
	result.range += mods.get("extra_range", 0.0)

func build_error(build: Dictionary, unlocked: Array, frame_level: int, frames_available: Array = []) -> String:
	var frame_id = build_frame(build)
	if not frames_available.is_empty() and not frames_available.has(frame_id):
		return "This frame is not available yet."
	var warhead = module(str(build.get("warhead", "")))
	if warhead == null or warhead.kind != ModuleData.Kind.WARHEAD or not unlocked.has(warhead.id):
		return "Select an unlocked warhead."
	if not fits(warhead.id, frame_id):
		return "%s does not fit the %s." % [warhead.display_name, frame(frame_id).display_name]
	var installed = build.get("modules", [])
	if installed.size() > slots(frame_level, frame_id):
		return "Not enough utility slots."
	var seen = []
	for id in installed:
		var item = module(id)
		if item == null or item.kind != ModuleData.Kind.UTILITY or not unlocked.has(id) or seen.has(id):
			return "Invalid or duplicate module."
		if not fits(id, frame_id):
			return "%s does not fit the %s." % [item.display_name, frame(frame_id).display_name]
		seen.append(id)
	if stats(build, frame_level).mass > max_mass(frame_level, frame_id):
		return "Frame mass limit exceeded."
	return ""
