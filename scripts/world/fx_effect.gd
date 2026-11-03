@tool
class_name FxEffect
extends Node3D
## Group of FxSprite children forming one effect (explosion, flak burst...).
## Frees itself when every child is done.

@export var random_offset := Vector3.ZERO

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	position += Vector3(randf_range(-1, 1) * random_offset.x, randf_range(-1, 1) * random_offset.y, randf_range(-1, 1) * random_offset.z)
	child_exiting_tree.connect(func(_c): if get_child_count() <= 1: queue_free())
