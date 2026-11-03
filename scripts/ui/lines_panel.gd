class_name LinesPanel
extends PanelContainer
## Bottom-left list of assembly lines (ui/hud/lines_panel.tscn).

@export var row_scene: PackedScene

@onready var rows: VBoxContainer = %Rows
@onready var count_label: Label = %Count
@onready var reserve_bar: ProgressBar = %ReserveBar
@onready var reserve_value: Label = %ReserveValue
@onready var reserve_down: Button = %ReserveDown
@onready var reserve_up: Button = %ReserveUp
@onready var add_button: Button = %AddLine
@onready var slot_button: Button = %SlotButton

@export var reserve_step := 25

var main: Node

func setup(game: Node) -> void:
	main = game
	reserve_down.pressed.connect(func(): main.sfx.play("click"); main.change_reserve(-reserve_step))
	reserve_up.pressed.connect(func(): main.sfx.play("click"); main.change_reserve(reserve_step))
	add_button.pressed.connect(func(): main.sfx.play("click"); main.open_editor(-1))
	slot_button.pressed.connect(func(): main.sfx.play("click"); main.buy_line_slot())
	main.state_changed.connect(_refresh)

func rebuild() -> void:
	for child in rows.get_children():
		rows.remove_child(child)
		child.queue_free()
	for item in main.sim.lines:
		var row = row_scene.instantiate()
		rows.add_child(row)
		row.setup(main, int(item.id))
	_refresh()

func _refresh() -> void:
	var sim = main.sim
	var paid = sim.paid_line_count()
	count_label.text = "%d / %d slots used" % [paid, sim.line_slots]
	%Subtitle.visible = paid == 0 or sim.lines.all(func(l): return l.free or l.route < 0)
	for row in rows.get_children():
		row.refresh()
	reserve_value.text = "%d cr" % int(sim.reserve)
	reserve_bar.max_value = maxf(100.0, sim.reserve * 2.0)
	reserve_bar.value = minf(sim.credits, reserve_bar.max_value)
	add_button.visible = paid < sim.line_slots
	add_button.disabled = sim.victory
	var price = sim.next_slot_price()
	slot_button.visible = paid >= sim.line_slots and price >= 0
	slot_button.text = "+  OPEN ANOTHER LINE SLOT · %d cr" % price
	slot_button.disabled = sim.credits < price
