class_name LineRow
extends PanelContainer
## One assembly line row (ui/hud/line_row.tscn). Drag it onto a route arrow.

@export var play_icon: Texture2D
@export var pause_icon: Texture2D
@export var unassigned_color := Color("5d6873")
@export var free_bar_color := Color("d9353b")
@export var paid_bar_color := Color("1fbecb")
@export_group("Status colors")
@export var status_ok_color := Color(0.45, 0.85, 0.55)
@export var status_warn_color := Color(1, 0.75, 0.3)
@export var status_bad_color := Color(1, 0.42, 0.38)

@onready var token: Label = %Token
@onready var title: Label = %Title
@onready var progress: ProgressBar = %Progress
@onready var value: Label = %Value
@onready var toggle: Button = %Toggle
@onready var edit: Button = %Edit
@onready var status_label: Label = %Status

var main: Node
var line_id := 0

func setup(game: Node, id: int) -> void:
	main = game
	line_id = id
	var item = main.sim.line(id)
	title.text = "Auto drones" if item.free else item.name
	_tint(progress, free_bar_color if item.free else paid_bar_color)
	toggle.pressed.connect(func(): main.sfx.play("click"); main.toggle_line(line_id))
	edit.pressed.connect(func():
		main.sfx.play("click")
		if main.sim.line(line_id).free:
			main.select("line", line_id)
		else:
			main.open_editor(line_id)
	)
	edit.text = "INFO" if item.free else "EDIT"
	edit.tooltip_text = "Show the free line's details" if item.free else "Change this line's drone: warhead and modules"
	gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			main.select("line", line_id)
	)
	refresh()

func refresh() -> void:
	var sim = main.sim
	var item = sim.line(line_id)
	if item.is_empty():
		return
	var stats = sim.line_stats(item)
	progress.value = 0.0 if item.order.is_empty() else 100.0 * (1.0 - item.order.remaining / maxf(item.order.duration, 0.001))
	value.visible = not item.free
	value.text = "%d cr" % stats.cost
	value.theme_type_variation = &"MutedValue" if item.free else &"CostValue"
	toggle.icon = pause_icon if item.enabled else play_icon
	toggle.text = "PAUSE" if item.enabled else "START"
	toggle.theme_type_variation = &"SmallButton" if item.enabled else &"StartButton"
	token.text = "FREE" if item.free else "L%d" % line_id
	var token_color: Color = main.world.route_color(int(item.route)) if item.route >= 0 else unassigned_color
	_style_token(token_color)
	toggle.tooltip_text = "Pause production (a paid order is kept)" if item.enabled else "Start building and launching drones"
	toggle.disabled = sim.victory
	var info = sim.status_info(item)
	status_label.text = info.text
	status_label.add_theme_color_override("font_color", {"ok": status_ok_color, "warn": status_warn_color, "bad": status_bad_color}[info.level])
	var selected = main.selected.kind == "line" and int(main.selected.id) == line_id
	_style_card(token_color, selected)
	tooltip_text = "%s · %s\n%s\n\nClick for details · drag onto a route arrow to change its route." % [item.name, info.text, info.hint]

func _get_drag_data(_at: Vector2) -> Variant:
	if main.editor.visible:
		return null
	var preview = PanelContainer.new()
	preview.theme = main.theme
	preview.theme_type_variation = &"DragPreview"
	var label = Label.new()
	label.text = "%s  >  drop on an arrow" % main.sim.line(line_id).name.to_upper()
	preview.add_child(label)
	set_drag_preview(preview)
	return {"kind": "line", "line_id": line_id}

static func _tint(bar: ProgressBar, color: Color) -> void:
	var fill = bar.get_theme_stylebox("fill").duplicate() as StyleBoxFlat
	if fill != null:
		fill.bg_color = color
		bar.add_theme_stylebox_override("fill", fill)

var _token_color := Color.TRANSPARENT
var _card_key := ""

func _style_token(color: Color) -> void:
	if color == _token_color:
		return
	_token_color = color
	var box = StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(4)
	box.content_margin_left = 6
	box.content_margin_right = 6
	token.add_theme_stylebox_override("normal", box)
	token.add_theme_color_override("font_color", Color(0.04, 0.06, 0.08) if color.get_luminance() > 0.45 else Color.WHITE)

## Card background with a stripe in the route colour on the left.
func _style_card(color: Color, selected: bool) -> void:
	var key = str(color) + str(selected)
	if key == _card_key:
		return
	_card_key = key
	var base = get_theme_stylebox("panel", &"LineRowSelected" if selected else &"LineRow").duplicate() as StyleBoxFlat
	if base == null:
		return
	base.border_width_left = 4
	base.border_color = color
	add_theme_stylebox_override("panel", base)
