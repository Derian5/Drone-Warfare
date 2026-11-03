@tool
class_name AirDefenseData
extends Resource
## How an enemy air-defense site fights. Assign to TargetData.air_defense.

enum Kind { GUN, MISSILE, JAMMER }

@export var kind: Kind = Kind.GUN
@export var display_name := "Flak Gun"
@export_multiline var description := ""
@export var icon: Texture2D
@export var radius := 18.0
## Higher = hits more often. Hit chance = accuracy / (accuracy + drone agility).
@export var accuracy := 36.0
@export var damage := 1.8
## Seconds between volleys.
@export var interval := 0.19
## How many drones one volley can engage. Flooding the zone overloads the site.
@export var targets_per_volley := 1
## Terrain between the site and the drone blocks the shot (radar shadow behind hills).
@export var needs_line_of_sight := true
## Visual speed of the projectile (map units / s), only for effects.
@export var projectile_speed := 60.0

@export_group("Jammer")
## Drone speed multiplier inside the jammer zone.
@export_range(0.1, 1.0) var jam_speed := 0.6
## Warhead accuracy multiplier for drones that were jammed on the way.
@export_range(0.1, 1.0) var jam_accuracy := 0.7

@export_group("")
## What beats this air defense, shown in the intel panel. Empty = default text for the type.
@export var counter_hint := ""

func counter_text() -> String:
	if not counter_hint.is_empty():
		return counter_hint
	return ["Maneuver and Armor plating; fly around the ring", "Decoy Flares; stay out of the ring", "EW Pod (immune to jamming)"][kind]

func kind_name() -> String:
	return ["gun", "missile", "jammer"][kind]
