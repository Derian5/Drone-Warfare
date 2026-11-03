@tool
class_name CampaignData
extends Resource
## Ordered list of regions and the tech tree.

@export var regions: Array[RegionData] = []
@export var techs: Array[TechData] = []
@export var tech_points_per_star := 1
