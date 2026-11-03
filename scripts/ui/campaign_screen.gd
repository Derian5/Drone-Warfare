class_name CampaignScreen
extends Control
## Campaign map: regions, stars and the tech tree (ui/campaign/campaign_screen.tscn).

@export var card_scene: PackedScene
@export var tech_scene: PackedScene

@onready var cards: Container = %Cards
@onready var techs_box: Container = %Techs
@onready var points_label: Label = %TechPoints
@onready var stars_label: Label = %TotalStars

var main: Node

func setup(game: Node) -> void:
	main = game
	visible = false
	%Close.pressed.connect(close)
	main.state_changed.connect(func(): if visible: refresh())

func open() -> void:
	show()
	_rebuild()

func close() -> void:
	hide()

func _rebuild() -> void:
	for child in cards.get_children() + techs_box.get_children():
		child.queue_free()
	var sim = main.sim
	for i in range(sim.region_count()):
		var card = card_scene.instantiate()
		cards.add_child(card)
		card.setup(main, i)
	for tech in main.campaign.techs:
		var tile = tech_scene.instantiate()
		techs_box.add_child(tile)
		tile.setup(main, tech)
	refresh()

func refresh() -> void:
	var sim = main.sim
	var total = 0
	for state in sim.region_states.values():
		total += int(state.get("stars", 0))
	points_label.text = "%d tech points" % sim.tech_points
	stars_label.text = "%d / %d stars" % [total, sim.region_count() * 3]
	for card in cards.get_children():
		card.refresh()
	for tile in techs_box.get_children():
		tile.refresh()
