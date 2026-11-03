@tool
class_name StatRow
extends HBoxContainer
## "Caption ........ value" row (ui/hud/stat_row.tscn).

@export var caption := "Caption":
	set(value):
		caption = value
		if is_node_ready():
			%Caption.text = value
@export var value_variation: StringName = &"StatValue"

func _ready() -> void:
	%Caption.text = caption
	%Value.theme_type_variation = value_variation

func set_value(text: String, variation: StringName = &"") -> void:
	%Value.text = text
	%Value.theme_type_variation = variation if variation != &"" else value_variation
