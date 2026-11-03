@tool
class_name TargetData
extends Resource
## Enemy objective. Placement is done in the region scene (Sites node).

@export var id := ""
@export var display_name := ""
@export_multiline var intel_text := ""
@export var icon: Texture2D
@export var max_hp := 300.0
@export var armor := 0.0
## Credits paid per point of real damage.
@export var payout_rate := 1.0
## Seconds until the target is repaired after destruction. 0 = never (main target).
@export var respawn_time := 15.0
## Destroying the main target captures the region.
@export var is_main_target := false
## Percent of max HP repaired per second while alive.
@export var regen_percent_per_second := 0.0
## Seconds without hits before regeneration starts. 0 = always regenerates.
@export var regen_delay := 0.0
## If set, this site shoots drones.
@export var air_defense: AirDefenseData
## Damage multiplier for warheads with anti_air bonus (cluster munitions).
@export var counts_as_air_defense := false
