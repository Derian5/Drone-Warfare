extends VBoxContainer
## Empty build site: choose one building (ui/hud/intel_pad_page.tscn).
## Choices come from data/balance.tres → site_buildings.

@export var panel_title := "BUILD SITE"
@export var option_scene: PackedScene = preload("res://ui/hud/building_option.tscn")
@export_multiline var info_text := "Pick ONE building for this site. The choice stays for the whole region."

var main: Node
var id := ""
var _options: Array = []

func setup(game: Node, pad_id: Variant) -> void:
	main = game
	id = str(pad_id)
	%Info.text = info_text
	for building in main.balance.site_buildings:
		var option = option_scene.instantiate() as BuildingOption
		%Options.add_child(option)
		option.setup(building)
		option.chosen.connect(func(building_id): main.sfx.play("click"); main.build_pad(id, building_id))
		_options.append(option)
	refresh()

func refresh() -> void:
	var sim = main.sim
	var built: SiteBuildingData = sim.site_building_of(id)
	%Options.visible = built == null
	%Info.visible = false
	%Name.visible = built != null
	%Name.text = built.display_name.to_upper() if built else "EMPTY BUILD SITE"
	if built == null:
		for option in _options:
			option.refresh(sim.building_price(id, option.building.id), sim.credits)
		%Hint.text = ""
		return
	var extra = ""
	match built.kind:
		SiteBuildingData.Kind.LAUNCH_PAD:
			extra = "Drag from this pad to a target to draw a route."
		SiteBuildingData.Kind.AIR_DEFENSE:
			extra = "Shoots hunters within %d km. Upgrade AIR DEFENSE (right panel) to make it stronger." % int(built.radius)
		SiteBuildingData.Kind.INCOME:
			extra = "All income now ×%s." % str(snappedf(sim.income_multiplier(), 0.01))
	%Hint.text = built.description + "\n\n" + extra
