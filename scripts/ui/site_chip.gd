class_name SiteChip
extends PanelContainer
## Map label under a site (ui/map/site_chip.tscn).

@export var base_title := "FORWARD BASE"
@export var main_target_bar := Color("e0453f")
@export var target_bar := Color("e3a13b")

@onready var title: Label = %Title
@onready var bar: ProgressBar = %Bar
@onready var status: Label = %Status

func _place(at: Vector2) -> void:
	reset_size()
	position = at - Vector2(size.x / 2, 0)

func show_base(at: Vector2) -> void:
	title.text = base_title
	bar.visible = false
	status.visible = false
	theme_type_variation = &"SiteChipFriendly"
	_place(at)

func show_pad(at: Vector2, pad: Dictionary, built: bool) -> void:
	title.text = "FORWARD PAD" if built else "BUILD SITE · %d cr" % pad.price
	bar.visible = false
	status.visible = false
	theme_type_variation = &"SiteChipFriendly" if built else &"SiteChipNeutral"
	_place(at)

func show_target(at: Vector2, obj: Dictionary, data: TargetData) -> void:
	title.text = str(obj.name).to_upper()
	var destroyed = obj.hp <= 0
	bar.visible = not destroyed
	status.visible = destroyed
	theme_type_variation = &"SiteChipWarning" if destroyed else &"SiteChipEnemy"
	if destroyed:
		status.text = "DESTROYED" if data != null and data.is_main_target else "REPAIR %ds" % ceili(obj.respawn)
	else:
		bar.value = obj.hp / obj.max_hp * 100.0
		LineRow._tint(bar, main_target_bar if data != null and data.is_main_target else target_bar)
	_place(at)
