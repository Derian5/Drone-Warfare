@tool
class_name StatBar
extends VBoxContainer
## Live stat with a bar and a preview of the change (ui/editor/stat_bar.tscn).

@export var stat_key := "damage"
@export var caption := "DAMAGE":
	set(value):
		caption = value
		if is_node_ready():
			%Caption.text = value
@export var max_value := 70.0
@export var bar_color := Color("1fbecb")
@export var gain_color := Color(0.24, 0.77, 0.42, 0.85)
@export var loss_color := Color(0.85, 0.21, 0.23, 0.9)
@export var track_color := Color("2b333c")
@export var bar_height := 7.0

var value := 0.0
var preview := 0.0

func _ready() -> void:
	%Caption.text = caption
	%Bars.draw.connect(_draw_bars)

func show_values(current: float, previewed: float) -> void:
	value = current
	preview = previewed
	%Number.text = "%.0f" % current
	var change = previewed - current
	%Delta.text = "" if is_zero_approx(change) else "%+.0f" % change
	%Delta.theme_type_variation = &"DeltaGood" if change > 0 else &"DeltaBad"
	%Bars.queue_redraw()

func _draw_bars() -> void:
	var bars: Control = %Bars
	var w = bars.size.x
	var y = (bars.size.y - bar_height) / 2
	bars.draw_rect(Rect2(0, y, w, bar_height), track_color)
	var base_w = w * clampf(value / max_value, 0, 1)
	var preview_w = w * clampf(preview / max_value, 0, 1)
	if preview_w > base_w:
		bars.draw_rect(Rect2(0, y, preview_w, bar_height), gain_color)
	bars.draw_rect(Rect2(0, y, base_w, bar_height), bar_color)
	if preview_w < base_w:
		bars.draw_rect(Rect2(preview_w, y, base_w - preview_w, bar_height), loss_color)
