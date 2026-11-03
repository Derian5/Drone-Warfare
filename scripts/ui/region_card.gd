class_name RegionCard
extends PanelContainer
## One region on the campaign screen (ui/campaign/region_card.tscn).

@export var star_on: Texture2D
@export var star_off: Texture2D

var main: Node
var index := 0

func setup(game: Node, region_index: int) -> void:
	main = game
	index = region_index
	var region: RegionData = main.campaign.regions[index]
	%Preview.texture = region.preview
	%Name.text = "%02d · %s" % [index + 1, region.display_name.to_upper()]
	%Subtitle.text = region.subtitle
	%Briefing.text = region.briefing
	%Play.pressed.connect(func():
		main.sfx.play("click")
		main.campaign_screen.close()
		main.start_region(index)
	)
	refresh()

func refresh() -> void:
	var sim = main.sim
	var region: RegionData = main.campaign.regions[index]
	var state = sim.region_states.get(region.id, {})
	var stars = int(state.get("stars", 0))
	for i in range(3):
		get_node("%%Star%d" % (i + 1)).texture = star_on if i < stars else star_off
	var unlocked = sim.region_unlocked(index)
	var current = index == sim.region_index and not sim.victory
	%Lock.visible = not unlocked
	%Play.disabled = not unlocked
	%Play.text = "CONTINUE" if current else ("REPLAY" if state.get("cleared", false) else "DEPLOY")
	%Goals.text = "★2: capture in %d:%02d · ★3: lose ≤ %d drones" % [int(region.star_time) / 60, int(region.star_time) % 60, region.star_max_losses]
	theme_type_variation = &"RegionCardCurrent" if index == sim.region_index else &"RegionCard"
