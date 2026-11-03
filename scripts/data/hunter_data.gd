@tool
class_name HunterData
extends Resource
## Enemy hunter drones that raid the player's base.

@export var enabled := true
@export var first_wave_after := 75.0
@export var wave_interval := 70.0
@export var wave_interval_jitter := 15.0
@export var drones_per_wave := 1
@export var hp := 30.0
@export var speed := 11.0
## Fraction of ALL credits taken when a hunter reaches the base.
@export_range(0, 1) var steal_fraction := 0.3
## Seconds a hit line stays disabled.
@export var disable_seconds := 25.0
## Damage of one click/tap on a hunter.
@export var click_damage := 12.0
@export_group("Flight path")
## How far the path bends sideways (share of the distance to the base).
@export_range(0, 1) var curve_strength := 0.35
## Side-to-side weaving on top of the curve (map units).
@export var weave_amplitude := 3.0
## Number of weaves along the whole path.
@export var weave_count := 3.0
@export_group("")
## Credits for shooting a hunter down by hand (rewards active play).
@export var tap_bounty := 10
@export var warning_text := "Hunter drones inbound! Click or tap them to shoot them down before they reach your base."
