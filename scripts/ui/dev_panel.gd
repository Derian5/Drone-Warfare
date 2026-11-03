class_name DevPanel
extends PanelContainer
## Developer tools (ui/dev/dev_panel.tscn). Exists only in debug builds: running from the
## Godot editor or a debug export. Release exports (the web build) remove it on start.
## F9 hides/shows the panel.

@export var speeds: PackedFloat32Array = PackedFloat32Array([1.0, 2.0, 3.0])
@export var credits_step := 1000

var main: Node

func setup(game: Node) -> void:
	main = game
	if not OS.is_debug_build():
		queue_free()
		return
	var speed_row: Container = %SpeedRow
	for child in speed_row.get_children():
		child.queue_free()
	var group = ButtonGroup.new()
	var buttons = []
	for value in speeds:
		var button = Button.new()
		button.text = "×%s" % str(value).trim_suffix(".0")
		button.toggle_mode = true
		button.button_group = group
		button.button_pressed = is_equal_approx(value, 1.0)
		button.theme_type_variation = &"SmallButton"
		button.tooltip_text = "Game speed ×%s (simulation runs faster, same results)" % str(value).trim_suffix(".0")
		button.pressed.connect(func(): main.time_scale = value; main.refresh())
		speed_row.add_child(button)
		buttons.append([button, value])
	main.state_changed.connect(func():
		for pair in buttons:
			pair[0].set_pressed_no_signal(is_equal_approx(pair[1], main.time_scale))
	)
	%CreditsButton.text = "+%d cr" % credits_step
	%CreditsButton.pressed.connect(func(): main.sim.credits += credits_step; main.refresh())
	%HuntersButton.pressed.connect(func(): main.sim.hunter_timer = 0.01)
	%WinButton.pressed.connect(_win)
	%Collapse.pressed.connect(func(): %Tools.visible = not %Tools.visible)

func _win() -> void:
	var hq = main.sim.main_target()
	if hq.is_empty() or main.sim.victory:
		return
	hq.hp = 1
	main.sim._impact({"target": hq.id, "stats": {"damage": 99999.0, "penetration": 999.0}, "line": 0})
	main.refresh()

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F9:
		visible = not visible
		get_viewport().set_input_as_handled()
