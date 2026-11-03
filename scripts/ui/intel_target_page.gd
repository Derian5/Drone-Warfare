extends VBoxContainer
## Target intelligence page (ui/hud/intel_target_page.tscn).
## Top: name, HP and a short summary of what matters. Full numbers are under MORE DETAILS.

@export var panel_title := "TARGET INTELLIGENCE"

## Remembered between selections so the player chooses once.
static var details_open := false

var main: Node
var id := ""

func setup(game: Node, target_id: Variant) -> void:
	main = game
	id = str(target_id)
	var data: TargetData = main.sim.target_data(id)
	%Name.text = data.display_name.to_upper() if data else id
	%Name.theme_type_variation = &"PageTitleEnemy" if data and data.is_main_target else &"PageTitle"
	%DrawHint.text = "To attack: drag from your base on the map and release on this target."
	%DetailsButton.pressed.connect(func():
		details_open = not details_open
		main.sfx.play("click")
		_apply_details()
	)
	_apply_details()
	refresh()

func _apply_details() -> void:
	%Details.visible = details_open
	%DetailsButton.text = "HIDE DETAILS" if details_open else "MORE DETAILS..."

func refresh() -> void:
	var sim = main.sim
	var t = sim.target(id)
	if t.is_empty():
		return
	var data: TargetData = sim.target_data(id)
	var fraction = t.hp / t.max_hp
	if t.hp > 0:
		%HpValue.text = "%d / %d" % [ceili(t.hp), int(t.max_hp)]
	else:
		%HpValue.text = "DESTROYED" if data.is_main_target else "REPAIR %ds" % ceili(t.respawn)
	%HpBar.value = fraction * 100.0
	%ArmorTile.set_value("%d" % sim.target_armor(id))
	%PayoutTile.set_value("%.2f" % t.rate, &"TileValueAmber")
	var sites = sim.air_defenses()
	%AaTile.set_value("%d" % sites.size())
	%AdaptTile.set_value("%d/%d" % [sim.adaptations.size(), sim.adaptation_budget()])
	var routes = sim.routes.filter(func(r): return r.target == id).size()
	%RoutesTile.set_value(str(routes))
	%HitsTile.set_value(str(int(sim.totals.hit)))
	%DrawHint.visible = routes == 0 and t.hp > 0
	%Summary.text = _summary(sim, t, data)
	var names = []
	for counter_id in sim.adaptations:
		var counter = sim.counter_by_id(counter_id)
		if counter:
			names.append(counter.display_name)
	var defense = "base defense" if names.is_empty() else ", ".join(names)
	var reward = sim.region_data.capture_reward if sim.region_data else 400
	%Info.text = data.intel_text.format({"reward": reward, "defense": defense, "respawn": int(data.respawn_time), "regen": data.regen_percent_per_second})
	var lines = []
	if data.air_defense != null and t.hp > 0:
		var p = sim.aa_profile(id)
		var ad: AirDefenseData = data.air_defense
		if p.kind == "jammer":
			lines.append("%s · radius %d · drones slowed to %d%%, warhead accuracy %d%%" % [ad.display_name, p.radius, p.jam_speed * 100, p.jam_accuracy * 100])
		else:
			lines.append("%s · radius %d · accuracy %d · damage %d · every %.1fs · %d target%s%s" % [ad.display_name, p.radius, p.accuracy, p.damage, p.interval, p.capacity, "s" if p.capacity > 1 else "", " · needs line of sight" if p.los else ""])
	if not names.is_empty():
		lines.append("Enemy adaptations: %s." % ", ".join(names))
	%AaInfo.text = "\n".join(lines)
	%AaInfo.visible = not lines.is_empty()

## Two or three short lines: what this target does and what to do about it.
func _summary(sim, t: Dictionary, data: TargetData) -> String:
	var out = []
	if t.hp <= 0:
		return "Destroyed." if data.is_main_target else "Destroyed · back online in %ds." % ceili(t.respawn)
	if data.is_main_target:
		var reward = sim.region_data.capture_reward if sim.region_data else 400
		out.append("Destroy it to capture the region (+%d cr)." % reward)
		if data.regen_percent_per_second > 0:
			out.append("Repairs %s%% HP every second — hit it with several lines at once." % str(data.regen_percent_per_second).trim_suffix(".0"))
	elif data.air_defense != null:
		var ad: AirDefenseData = data.air_defense
		out.append("%s — shoots drones inside its ring." % ad.display_name if ad.kind != AirDefenseData.Kind.JAMMER else "%s — slows drones and spoils their aim." % ad.display_name)
		out.append("Beaten by: %s." % ad.counter_text())
	else:
		out.append("Undefended. Earns %.2f cr per damage point — good steady income." % t.rate)
	if data.air_defense != null and data.is_main_target:
		out.append("Close-in guns: %s." % data.air_defense.counter_text())
	return "\n".join(out)
