class_name Callouts
extends Control
## Labels connected to module slots on the editor preview drone.

@export var line_color := Color("1fbecb")
@export var line_width := 2.0
@export var box_color := Color(0.96, 0.97, 0.97, 0.95)
@export var text_color := Color("1d2a30")
@export var font_size := 12
## Where label boxes are placed, as fractions of the preview size.
@export var slots: PackedVector2Array = [Vector2(0.06, 0.12), Vector2(0.72, 0.12), Vector2(0.06, 0.8), Vector2(0.72, 0.8), Vector2(0.72, 0.46)]

var camera: Camera3D
var viewport: SubViewport
## [{"label": String, "node": Node3D}]
var items: Array = []

func _process(_delta: float) -> void:
	if is_visible_in_tree():
		queue_redraw()

func _draw() -> void:
	if camera == null or viewport == null or not camera.is_inside_tree():
		return
	var view_size = Vector2(viewport.size)
	var font = get_theme_font("font", "Button")
	var index = 0
	for item in items:
		if index >= slots.size() or not is_instance_valid(item.node):
			continue
		var screen = camera.unproject_position(item.node.global_position) / view_size * size
		var slot = slots[index] * size
		index += 1
		var w = font.get_string_size(item.label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + 18
		var rect = Rect2(slot, Vector2(w, 24))
		var attach = rect.get_center() + Vector2(w * 0.5 if slot.x < size.x * 0.5 else -w * 0.5, 0)
		draw_line(attach, screen, line_color, line_width, true)
		draw_circle(screen, 3.5, line_color)
		var style = StyleBoxFlat.new()
		style.bg_color = box_color
		style.set_corner_radius_all(2)
		style.set_border_width_all(1)
		style.border_color = line_color
		draw_style_box(style, rect)
		draw_string(font, rect.position + Vector2(9, 16.5), item.label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, text_color)
