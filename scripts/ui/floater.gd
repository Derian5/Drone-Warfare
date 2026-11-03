class_name Floater
extends Label
## Floating combat text (+income, MISS, DOWN). Colors per kind are set here.

@export var income_color := Color("ffd34d")
@export var miss_color := Color("f1f1ea")
@export var lost_color := Color("ff5a4e")
@export var income_size := 17
@export var small_size := 12

func show_text(value: String, kind: String, at: Vector2, alpha: float) -> void:
	text = value
	var color = income_color
	var font_size = income_size
	if kind == "lost":
		color = lost_color
		font_size = small_size
	elif kind == "miss":
		color = miss_color
		font_size = small_size + 1
	add_theme_font_size_override("font_size", font_size)
	add_theme_color_override("font_color", color)
	modulate.a = alpha
	position = at - Vector2(12, 0)
