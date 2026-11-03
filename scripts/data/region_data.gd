@tool
class_name RegionData
extends Resource
## One campaign region. The scene holds the map; this resource holds its rules.

@export var id := ""
@export var display_name := ""
@export var subtitle := ""
@export_multiline var briefing := ""
@export var preview: Texture2D
## Battlefield scene of this region (see scenes/regions).
@export var scene: PackedScene

@export_group("Enemy")
@export var hp_multiplier := 1.0
@export var aa_damage_multiplier := 1.0
@export var payout_multiplier := 1.0
@export var adaptation_budget := 3
## Each further adaptation is this much stronger (0.25 = +25% per step).
@export var adaptation_escalation := 0.25
@export var hunters: HunterData

@export_group("Rewards")
@export var capture_reward := 400
## Star 2: capture within this many seconds.
@export var star_time := 480.0
## Star 3: lose at most this many paid drones.
@export var star_max_losses := 12

@export_group("Content")
## Modules that become available for research in this region.
@export var new_modules: Array[ModuleData] = []
## Frames that become available (free) when this region opens.
@export var new_frames: Array[FrameData] = []
@export var camera_zoom := 1.0
