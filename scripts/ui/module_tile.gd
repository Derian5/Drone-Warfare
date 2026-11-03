class_name ModuleTile
extends Button
## Catalog tile in the assembly editor (ui/editor/module_tile.tscn).

signal hovered(id: String, inside: bool)

@export var affordable_color := Color("f2a71b")
@export var unaffordable_color := Color("ff8a80")

var module: ModuleData

func _ready() -> void:
	# Caption sits under the picture; keep it clear of the check badge.
	%Caption.custom_minimum_size = Vector2(78, 0)
	%Caption.size = Vector2(78, 30)

func setup(data: ModuleData) -> void:
	module = data
	%Picture.texture = data.icon
	tooltip_text = "%s\n%s\n%s\nMass %d · +%d cr per drone" % [data.display_name, data.purpose, ", ".join(data.effects()), data.mass, data.cost_per_drone]
	%Tag.visible = not data.frames.is_empty()
	%Tag.text = " " + ", ".join(Array(data.frames)).to_upper() + " ONLY "
	mouse_entered.connect(func(): hovered.emit(module.id, true))
	mouse_exited.connect(func(): hovered.emit(module.id, false))

func refresh(installed: bool, unlocked: bool, credits: float) -> void:
	%Caption.text = module.display_name
	%Lock.visible = not unlocked
	%LockText.text = "UNLOCK\n%d cr" % module.unlock_cost
	%LockText.add_theme_color_override("font_color", affordable_color if credits >= module.unlock_cost else unaffordable_color)
	%Badge.visible = installed
	theme_type_variation = &"ModuleTileInstalled" if installed else &"ModuleTile"
