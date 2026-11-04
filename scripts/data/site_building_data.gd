@tool
class_name SiteBuildingData
extends Resource
## A building the player can put on an empty build site (data/site_buildings/*.tres).
## One building per site; the choice stays for the whole region.

enum Kind { LAUNCH_PAD, AIR_DEFENSE, INCOME }

@export var id := ""
@export var kind: Kind = Kind.LAUNCH_PAD
@export var display_name := ""
## One line shown on the choice button.
@export var short_text := ""
@export_multiline var description := ""
## Price = build site price × this.
@export var price_multiplier := 1.0
## Model shown on the site once built (empty = the site's own built node).
@export var scene: PackedScene

@export_group("Air defense tower")
@export var radius := 16.0
@export var damage := 3.0
@export var interval := 0.2

@export_group("Income")
## Multiplies all credits earned from hits (several buildings multiply together).
@export var income_multiplier := 1.5
