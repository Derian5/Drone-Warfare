@tool
class_name IntelTile
extends VBoxContainer
## Stat tile: big value with a small caption (ui/hud/intel_tile.tscn).
## The picture is optional (show_picture) — numbers matter more than images here.

@export var picture: Texture2D:
	set(value):
		picture = value
		if is_node_ready():
			%Picture.texture = value
@export var show_picture := false:
	set(value):
		show_picture = value
		if is_node_ready():
			%Picture.visible = value
@export var caption := "CAPTION":
	set(value):
		caption = value
		if is_node_ready():
			%Caption.text = value

func _ready() -> void:
	%Picture.texture = picture
	%Picture.visible = show_picture
	%Caption.text = caption

func set_value(text: String, variation: StringName = &"TileValue") -> void:
	%Value.text = text
	%Value.theme_type_variation = variation
