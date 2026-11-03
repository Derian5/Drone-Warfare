@tool
class_name TechData
extends Resource
## Permanent upgrade bought with tech points (earned from region stars).

@export var id := ""
@export var display_name := ""
@export_multiline var description := ""
@export var icon: Texture2D
@export var cost := 1
@export var requires: Array[TechData] = []

@export_group("Effects (multipliers, 1 = no change)")
@export var drone_damage := 1.0
@export var drone_hp := 1.0
@export var drone_speed := 1.0
@export var drone_cost := 1.0
@export var build_time := 1.0
@export var income := 1.0
@export var hunter_steal := 1.0
@export var base_defense_damage := 1.0
@export_group("Effects (flat)")
@export var extra_agility := 0.0
@export var extra_range := 0.0
@export var extra_reserve_protection := 0
