class_name VictoryPanel
extends CenterContainer
## Region results with stars (ui/hud/victory_panel.tscn).

@export var star_on: Texture2D
@export var star_off: Texture2D

@onready var title: Label = %Title
@onready var body: Label = %Body
@onready var next_button: Button = %NextButton
@onready var campaign_button: Button = %CampaignButton

var main: Node

func setup(game: Node) -> void:
	main = game
	next_button.pressed.connect(func(): main.sfx.play("click"); main.next_region())
	campaign_button.pressed.connect(func(): main.sfx.play("click"); main.open_campaign())
	main.state_changed.connect(_refresh)

func _refresh() -> void:
	var sim = main.sim
	visible = sim.victory and not main.campaign_screen.visible
	if not visible or sim.result.is_empty():
		return
	var r = sim.result
	title.text = "%s CAPTURED" % (sim.region_data.display_name.to_upper() if sim.region_data else "REGION")
	for i in range(3):
		get_node("%%Star%d" % (i + 1)).texture = star_on if i < r.stars else star_off
	%CriterionCapture.text = "Region captured"
	%CriterionTime.text = "Captured in %d:%02d (limit %d:%02d)" % [int(r.time) / 60, int(r.time) % 60, int(r.time_limit) / 60, int(r.time_limit) % 60]
	%CriterionTime.theme_type_variation = &"StatValueGood" if r.time_ok else &"StatValueBad"
	%CriterionLosses.text = "Drones lost: %d (limit %d)" % [r.losses, r.loss_limit]
	%CriterionLosses.theme_type_variation = &"StatValueGood" if r.losses_ok else &"StatValueBad"
	body.text = "Reward +%d cr%s · +%d tech points" % [r.reward, "" if r.first_clear else " (replay)", r.tech_points]
	var has_next = sim.region_index + 1 < sim.region_count()
	next_button.visible = has_next
