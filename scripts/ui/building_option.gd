class_name BuildingOption
extends PanelContainer
## One choice on an empty build site (ui/hud/building_option.tscn).

signal chosen(building_id: String)

var building: SiteBuildingData

func setup(data: SiteBuildingData) -> void:
	building = data
	%Name.text = data.display_name
	%Short.text = data.short_text
	%Description.text = data.description
	%Description.visible = false
	tooltip_text = "%s\n%s" % [data.display_name, data.description]
	%Build.pressed.connect(func(): chosen.emit(building.id))

func refresh(price: int, credits: float) -> void:
	%Build.text = "BUILD · %d cr" % price
	%Build.disabled = credits < price
	%Build.tooltip_text = "" if credits >= price else "Not enough credits yet."
