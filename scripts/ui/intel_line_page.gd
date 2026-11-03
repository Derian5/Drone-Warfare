extends VBoxContainer
## Assembly line page (ui/hud/intel_line_page.tscn).

@export var panel_title := "ASSEMBLY LINE"

var main: Node
var id := 0

func setup(game: Node, line_id: Variant) -> void:
	main = game
	id = int(line_id)
	var sim = main.sim
	var item = sim.line(id)
	%Name.text = ("FREE DRONE AUTO" if item.free else "L%d · %s" % [id, item.name]).to_upper()
	if item.free:
		%Parts.visible = false
	else:
		var parts = []
		for module_id in [item.build.warhead] + item.build.modules:
			var module = sim.balance.module(module_id)
			if module:
				parts.append(module.display_name)
		%Parts.text = " + ".join(parts)
	var picker: OptionButton = %RoutePicker
	picker.add_item("No route", 0)
	picker.set_item_metadata(0, -1)
	for path in sim.routes:
		picker.add_item("R%d  >  %s" % [path.id, sim.target(path.target).name])
		picker.set_item_metadata(picker.item_count - 1, path.id)
		if item.route == path.id:
			picker.select(picker.item_count - 1)
	picker.item_selected.connect(func(index):
		var route_id = int(picker.get_item_metadata(index))
		if route_id < 0:
			main.sim.line(id).route = -1
		else:
			main.sim.assign(id, route_id)
		main.committed()
	)
	%Toggle.pressed.connect(func(): main.sfx.play("click"); main.toggle_line(id))
	%Edit.visible = not item.free
	%Edit.pressed.connect(func(): main.sfx.play("click"); main.open_editor(id))
	refresh()

func refresh() -> void:
	var sim = main.sim
	var item = sim.line(id)
	if item.is_empty():
		return
	var stats = sim.line_stats(item)
	var info = sim.status_info(item)
	%Status.text = "%s\n%s" % [info.text, info.hint] if info.level != "ok" else info.text
	%Status.theme_type_variation = {"ok": &"StatValueGood", "warn": &"StatValueAmber", "bad": &"StatValueBad"}[info.level]
	%Cost.set_value("FREE" if item.free else "%d cr" % stats.cost)
	%BuildTime.set_value("%.1f s" % stats.interval)
	%Launched.set_value(str(int(item.launched)))
	%Hits.set_value(str(int(item.hit)))
	%Losses.set_value(str(int(item.lost)))
	%Misses.set_value(str(int(item.get("miss", 0))))
	%Income.set_value("%d cr" % int(item.income))
	%Spent.set_value("%d cr" % int(item.spent))
	var profit = item.income - item.spent
	%Net.set_value("%+d cr" % int(profit), &"StatValueGood" if profit >= 0 else &"StatValueBad")
	%Toggle.text = "PAUSE LINE" if item.enabled else "START LINE"
	%Range.set_value("%.0f km" % stats.range)
	var reasons = []
	var names = {"gun": "flak guns", "missile": "missiles", "jammer": "jammers", "unknown": "other"}
	for key in item.get("lost_by", {}):
		reasons.append("%s %d" % [names.get(key, key), item.lost_by[key]])
	%LostBy.text = ("Shot down by: " + ", ".join(reasons)) if not reasons.is_empty() else "No losses yet."
