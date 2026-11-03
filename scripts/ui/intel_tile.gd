@tool
class_name IntelTile
extends VBoxContainer
## Small picture tile with a caption and a value (ui/hud/intel_tile.tscn).

@export var picture: Texture2D:
	set(value):
		picture = value
		if is_node_ready():
			%Picture.texture = value
@export var caption := "CAPTION":
	set(value):
		caption = value
		if is_node_ready():
			%Caption.text = value

func _ready() -> void:
	%Picture.texture = picture
	%Caption.text = caption

func set_value(text: String, variation: StringName = &"TileValue") -> void:
	%Value.text = text
	%Value.theme_type_variation = variation
