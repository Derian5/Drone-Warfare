@tool
class_name ModuleData
extends Resource
## One drone module (warhead or utility). Edit values in the inspector.

enum Kind { WARHEAD, UTILITY }
## Group in the assembly editor.
enum Category { WARHEAD, PROTECTION, MOBILITY, ELECTRONICS, PAYLOAD }

@export var id := ""
@export var display_name := ""
@export var short_name := ""
@export var kind: Kind = Kind.UTILITY
@export var category: Category = Category.PROTECTION
## Short effect summary (one line).
@export_multiline var description := ""
## Why/when to take it. Shown when the player hovers the module.
@export_multiline var purpose := ""
## Frames that can carry this module (FrameData ids). Empty = every frame.
## Modules for other frames are hidden in the editor.
@export var frames: PackedStringArray = []
@export var icon: Texture2D
## Scene attached to the drone when this module is installed.
@export var part_scene: PackedScene
## Name of the Marker3D on the drone scene the part is attached to.
@export var slot := ""
## Label shown in the editor callout.
@export var callout := ""

@export_group("Economy")
@export var unlock_cost := 0
@export var cost_per_drone := 0
@export var mass := 1

@export_group("Stat changes")
@export var damage := 0.0
@export var hp := 0.0
@export var speed := 0.0
@export var agility := 0.0
@export var penetration := 0.0
## Extra flight range (map units). Routes longer than the drone's range cannot be flown.
@export var flight_range := 0.0
## Number of air-defense hits the drone ignores (flares / decoys).
@export var decoys := 0
## Electronic warfare pod: immune to jammers, enemy accuracy against it is multiplied.
@export var ew_pod := false
@export_range(0.1, 1.0) var ew_enemy_accuracy := 0.75
## Warhead accuracy change (0.05 = +5 percentage points).
@export var accuracy := 0.0
## Multiplies enemy air-defense accuracy against this drone (stealth). Stacks with EW.
@export_range(0.1, 1.0) var enemy_accuracy := 1.0
## Damage multiplier against air-defense sites (cluster munitions).
@export var anti_air_multiplier := 1.0
## Extra armor the warhead has to beat (weak against fortifications).
@export var armor_penalty := 0.0

@export_group("Adaptation")
## When most paid HQ attackers carry this module, the enemy may install this counter.
@export var counter: CounterData

## Human-readable effect list, e.g. ["+60 HP", "−4 speed"]. Used by the editor.
func effects() -> PackedStringArray:
	var out: PackedStringArray = []
	var add = func(value: float, text: String, percent := false):
		if absf(value) > 0.0001:
			out.append(("%+d%% " % roundi(value * 100) if percent else "%+d " % roundi(value)).replace("-", "−") + text)
	add.call(damage, "damage")
	add.call(penetration, "armor penetration")
	add.call(hp, "HP")
	add.call(speed, "speed")
	add.call(agility, "agility")
	add.call(flight_range, "range")
	add.call(accuracy, "accuracy", true)
	if decoys > 0:
		out.append("%d decoy vs missiles" % decoys)
	if ew_pod:
		out.append("immune to jammers")
		out.append("enemy accuracy −%d%%" % roundi((1.0 - ew_enemy_accuracy) * 100))
	if enemy_accuracy < 1.0:
		out.append("enemy accuracy −%d%%" % roundi((1.0 - enemy_accuracy) * 100))
	if anti_air_multiplier != 1.0:
		out.append("×%s damage vs air defense" % str(snappedf(anti_air_multiplier, 0.1)))
	if armor_penalty > 0:
		out.append("weak vs armor (+%d)" % roundi(armor_penalty))
	return out
