class_name TopBar
extends PanelContainer
## ui/hud/top_bar.tscn

@export var sound_on_icon: Texture2D
@export var sound_off_icon: Texture2D
@export var negative_color := Color("ff8a80")

@onready var objective: Label = %Objective
@onready var credits: Label = %Credits
@onready var net: Label = %Net
@onready var sound_button: Button = %SoundButton
@onready var help_button: Button = %HelpButton
@onready var reset_button: Button = %ResetButton
@onready var pause_button: Button = %PauseButton
@onready var speed_button: Button = %SpeedButton
@onready var region_label: Label = %RegionLabel
@onready var campaign_button: Button = %CampaignButton

var main: Node

func setup(game: Node) -> void:
	main = game
	sound_button.pressed.connect(func(): main.sfx.play("click"); main.toggle_sound())
	help_button.pressed.connect(func(): main.sfx.play("click"); main.help_dialog.popup_centered(Vector2i(640, 440)))
	reset_button.pressed.connect(func(): main.sfx.play("click"); main.reset_dialog.popup_centered())
	pause_button.pressed.connect(func(): main.sfx.play("click"); main.toggle_pause())
	speed_button.pressed.connect(func(): main.sfx.play("click"); main.toggle_speed())
	campaign_button.pressed.connect(func(): main.sfx.play("click"); main.open_campaign())
	main.state_changed.connect(_refresh)

func _refresh() -> void:
	var sim = main.sim
	objective.text = main.objective()
	var region = sim.region_data
	region_label.text = ("%02d · %s" % [sim.region_index + 1, region.display_name.to_upper()]) if region else ""
	campaign_button.text = "CAMPAIGN · %d TP" % sim.tech_points if sim.tech_points > 0 else "CAMPAIGN"
	credits.text = "%d" % int(sim.credits)
	var value = main.net_per_minute()
	net.text = "Net %+d/min" % roundi(value)
	if value < 0:
		net.add_theme_color_override("font_color", negative_color)
	else:
		net.remove_theme_color_override("font_color")
	sound_button.icon = sound_off_icon if main.muted else sound_on_icon
	pause_button.text = "Resume" if main.paused else ("Paused" if main.backgrounded else "Pause")
	speed_button.text = "×%s" % str(main.time_scale).trim_suffix(".0")
	speed_button.theme_type_variation = &"StartButton" if main.time_scale > 1.0 else &"PillButton"
	speed_button.tooltip_text = ("Game runs at ×%s. Click for normal speed (F)." % str(main.time_scale).trim_suffix(".0")) if main.time_scale > 1.0 else "Game runs at normal speed. Click for double speed (F)."
