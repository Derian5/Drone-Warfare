@tool
class_name FrameData
extends Resource
## A drone frame (airframe). Each frame has its own base stats, look and exclusive modules.
## Frames are listed in data/balance.tres (frames) and unlocked by regions (RegionData.new_frames).

@export var id := ""
@export var display_name := ""
@export var short_name := ""
## One line: what the frame is good at.
@export var role := ""
## Longer text shown in the editor: when to choose this frame.
@export_multiline var description := ""
@export var icon: Texture2D
## Drone scene with Marker3D slots (SlotWarhead, SlotArmor, SlotBooster, SlotPayload, SlotFins).
@export var drone_scene: PackedScene
## Scale of the model on the map.
@export var map_scale := 1.0

@export_group("Base stats")
@export var hp := 26.0
@export var speed := 18.0
@export var agility := 18.0
## Flight range in map units (route length).
@export var flight_range := 180.0
@export var damage_bonus := 0.0
@export_range(0, 1) var accuracy := 0.92
@export var slots := 2
@export var max_mass := 8
@export var cost := 9
@export var build_time := 3.5
