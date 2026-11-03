@tool
class_name DroneView
extends Node3D
## Drone scene root. Module parts (ModuleData.part_scene) are attached to Marker3D slots.
## Nodes whose names start with rotor_prefix spin around spin_axis.

@export var rotor_prefix := "Rotor"
@export var spin_axis := Vector3.UP
@export var spin_speed := 40.0
## Gentle banking/bobbing while flying.
@export var bob_height := 0.12
@export var bank_amount := 0.06
## Optional effect spawned periodically behind boosted drones (set by the battlefield).
@export var trail_offset := Vector3(0, 0, 1.2)

var _rotors: Array = []
var _parts: Array = []
var _time := 0.0
var build: Dictionary = {}

func _ready() -> void:
	_rotors = find_children(rotor_prefix + "*", "Node3D", true, false)

## Installs module parts for this build. Returns {module_id: Marker3D} for editor callouts.
func apply_build(new_build: Dictionary, balance: GameBalance) -> Dictionary:
	build = new_build
	for part in _parts:
		if is_instance_valid(part):
			part.get_parent().remove_child(part)
			part.queue_free()
	_parts.clear()
	var anchors = {}
	if balance == null:
		return anchors
	var ids = []
	if build.has("warhead"):
		ids.append(build.warhead)
	ids.append_array(build.get("modules", []))
	for id in ids:
		var module = balance.module(id)
		if module == null or module.part_scene == null:
			continue
		var slot = find_child(module.slot, true, false) as Node3D
		if slot == null:
			slot = self
		var part = module.part_scene.instantiate()
		slot.add_child(part)
		_parts.append(part)
		anchors[id] = slot
	_rotors = find_children(rotor_prefix + "*", "Node3D", true, false)
	return anchors

func spin(delta: float) -> void:
	_time += delta
	for rotor in _rotors:
		rotor.rotate_object_local(spin_axis, delta * spin_speed)

func wobble(seed_value: float) -> Vector3:
	return Vector3(0, sin(_time * 3.0 + seed_value) * bob_height, 0)

func bank(seed_value: float) -> float:
	return sin(_time * 1.7 + seed_value) * bank_amount
