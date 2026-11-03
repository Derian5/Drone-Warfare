@tool
extends Node3D
## Slowly rotates a node (planet clouds, radar dishes...).

@export var speed := 0.05
@export var axis := Vector3.UP

func _process(delta: float) -> void:
	rotate(axis.normalized(), speed * delta)
