@tool
class_name CounterData
extends Resource
## Enemy adaptation installed in response to a popular module or a popular route.
## Multipliers grow with every further adaptation (see RegionData.adaptation_escalation).

@export var id := ""
@export var display_name := ""
@export_multiline var description := ""
@export var icon: Texture2D
## Which air-defense kinds are affected: "gun", "missile", "jammer". Empty = all.
@export var affects: PackedStringArray = []
@export var accuracy_multiplier := 1.0
@export var damage_multiplier := 1.0
@export var interval_multiplier := 1.0
@export var radius_multiplier := 1.0
@export var capacity_bonus := 0
## Added to the armor of the main target.
@export var main_target_armor_bonus := 0.0
## Instead of upgrading, activate the reserve air-defense site closest to the busiest route.
@export var deploys_reserve_site := false
