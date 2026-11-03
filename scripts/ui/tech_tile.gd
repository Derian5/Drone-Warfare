class_name TechTile
extends PanelContainer
## One technology in the campaign tech tree (ui/campaign/tech_tile.tscn).

var main: Node
var tech: TechData

func setup(game: Node, data: TechData) -> void:
	main = game
	tech = data
	%Icon.texture = data.icon
	%Name.text = data.display_name
	%Description.text = data.description
	%Buy.pressed.connect(func(): main.buy_tech(tech.id))
	refresh()

func refresh() -> void:
	var sim = main.sim
	var owned = sim.techs.has(tech.id)
	var available = sim.tech_available(tech)
	%Buy.visible = not owned
	%Buy.text = "%d TP" % tech.cost
	%Buy.disabled = not available or sim.tech_points < tech.cost
	%Owned.visible = owned
	var missing = []
	for requirement in tech.requires:
		if requirement != null and not sim.techs.has(requirement.id):
			missing.append(requirement.display_name)
	%Requires.text = ("Requires: " + ", ".join(missing)) if not missing.is_empty() else ""
	theme_type_variation = &"TechTileOwned" if owned else (&"TechTile" if available else &"TechTileLocked")
