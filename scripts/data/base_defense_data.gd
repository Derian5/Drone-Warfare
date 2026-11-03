@tool
class_name BaseDefenseData
extends Resource
## One level of the player's base air defense (shoots hunters).

@export var display_name := "Base AA"
@export var price := 150
@export var radius := 14.0
@export var damage := 12.0
@export var interval := 1.0
## Base AA only cripples hunters: it never takes them below this share of their HP.
## The final shot has to be a tap/click.
@export_range(0, 1) var min_hp_fraction := 0.34
## Speed multiplier for hunters inside the AA radius (more time to tap them).
@export_range(0.1, 1) var slow_factor := 0.6
