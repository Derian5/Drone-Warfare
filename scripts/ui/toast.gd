class_name Toast
extends PanelContainer
## Bottom-centre notice / air-defense warning (ui/hud/toast.tscn).

@export var warning_icon: Texture2D
@export var info_icon: Texture2D
@export var notice_seconds := 5.0
@export var fade_seconds := 0.4

@onready var icon: TextureRect = %Icon
@onready var title: Label = %Title
@onready var body: Label = %Body

var main: Node
var _timer := 0.0

func setup(game: Node) -> void:
	main = game
	modulate.a = 0.0
	main.state_changed.connect(_refresh)

func _refresh() -> void:
	var sim = main.sim
	visible = not main.editor.visible and not main.campaign_screen.visible
	if not sim.pending_adaptation.is_empty():
		var counter = sim.balance.counter(sim.pending_adaptation)
		_show("AIR DEFENSE", "ADAPTING %ds · %s" % [ceili(sim.adaptation_timer), counter.display_name.to_upper() if counter else ""], true, 0.5)

func notice(text: String, pending: String) -> void:
	if not pending.is_empty() and not text.begins_with("Air defense"):
		return
	var hunters = text.begins_with("Hunter")
	var warning = hunters or text.begins_with("Air defense") or text.begins_with("Not enough") or text.begins_with("Could not")
	var heading = "AIR DEFENSE" if text.begins_with("Air defense") else ("HUNTERS" if hunters else ("WARNING" if warning else "COMMAND"))
	_show(heading, text, warning, notice_seconds)

func _show(heading: String, text: String, warning: bool, seconds: float) -> void:
	icon.texture = warning_icon if warning else info_icon
	title.text = heading
	body.text = text
	theme_type_variation = &"ToastWarning" if warning else &"Toast"
	title.theme_type_variation = &"ToastTitleWarning" if warning else &"ToastTitle"
	body.theme_type_variation = &"ToastBodyWarning" if warning else &"ToastBody"
	modulate.a = 1.0
	_timer = maxf(_timer, seconds) if warning else seconds

func _process(delta: float) -> void:
	if _timer > 0:
		_timer -= delta
		if _timer <= 0:
			create_tween().tween_property(self, "modulate:a", 0.0, fade_seconds)
