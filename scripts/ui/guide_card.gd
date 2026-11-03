class_name GuideCard
extends PanelContainer
## "What to do now" card at the top of the right panel (ui/hud/guide_card.tscn).
## Shows the next tutorial step, or an alert (hunters, adaptation, a line that needs help).
## Hidden when nothing needs the player's attention. Texts come from main.guide().

@export var step_color := Color("1fbecb")
@export var alert_color := Color("ff6b5e")
@export var info_color := Color("f2a71b")

var main: Node

func setup(game: Node) -> void:
	main = game
	main.state_changed.connect(_refresh)
	%Hide.pressed.connect(func(): main.guide_dismissed = true; main.sfx.play("click"); _refresh())

func _refresh() -> void:
	var g: Dictionary = main.guide()
	visible = not g.is_empty()
	if not visible:
		return
	var color = {"step": step_color, "alert": alert_color, "info": info_color}[g.get("kind", "step")]
	%Stripe.color = color
	%Kicker.text = g.get("kicker", "")
	%Kicker.add_theme_color_override("font_color", color)
	%Title.text = g.get("title", "")
	%Body.text = g.get("body", "")
	%Hide.visible = g.get("kind", "step") == "step"
