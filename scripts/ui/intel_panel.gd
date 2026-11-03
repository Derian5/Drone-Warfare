class_name IntelPanel
extends PanelContainer
## Right sidebar (ui/hud/intel_panel.tscn): 3D preview of the selection, a page per
## selection kind, the reserve caption and the BOOST button.

@export var target_page: PackedScene
@export var base_page: PackedScene
@export var route_page: PackedScene
@export var line_page: PackedScene
@export var pad_page: PackedScene
@export var preview_spin_speed := 0.35
@export var drone_preview_scale := 3.6

@onready var title: Label = %Title
@onready var close_button: Button = %Close
@onready var model_holder: Node3D = %ModelHolder
@onready var pages: Container = %Pages
@onready var reserve_caption: Label = %ReserveCaption
@onready var boost_button: Button = %BoostButton

var main: Node
var _page: Node
var _model: Node3D

func setup(game: Node) -> void:
	main = game
	close_button.pressed.connect(func(): main.select("target", main.main_target_id()))
	boost_button.pressed.connect(func(): main.sfx.play("click"); main.boost())
	main.state_changed.connect(_refresh)

func show_selection(kind: String, id: Variant) -> void:
	if main == null:
		return
	var sim = main.sim
	if kind == "route" and sim.route(int(id)).is_empty() or kind == "line" and sim.line(int(id)).is_empty() or kind == "target" and sim.target(str(id)).is_empty() or kind == "pad" and sim.build_site(str(id)).is_empty():
		kind = "target"
		id = main.main_target_id()
	if _page != null:
		_page.queue_free()
	var scene = {"target": target_page, "base": base_page, "route": route_page, "line": line_page, "pad": pad_page}[kind]
	_page = scene.instantiate()
	pages.add_child(_page)
	_page.setup(main, id)
	title.text = _page.panel_title
	_show_model(kind, id)
	_refresh()

func _show_model(kind: String, id: Variant) -> void:
	if is_instance_valid(_model):
		_model.queue_free()
	var sim = main.sim
	var site: MapSite = null
	if kind == "target":
		site = main.world.site_for(str(id))
	elif kind == "base":
		site = main.world.site_for("base")
	elif kind == "route":
		site = main.world.site_for(sim.route(int(id)).target)
	elif kind == "pad":
		site = main.world.site_for(str(id))
	if site != null:
		for child in site.get_children():
			if child is Node3D and child.name != "Outline":
				_model = child.duplicate()
				break
		if _model != null:
			model_holder.add_child(_model)
			_model.position = Vector3.ZERO
			_model.scale = Vector3.ONE
	elif kind == "line":
		var item = sim.line(int(id))
		_model = main.world.spawn_drone_model(model_holder, item.free, item.build)
		_model.scale = Vector3.ONE * drone_preview_scale
		_model.position.y = 3

func _process(delta: float) -> void:
	if is_instance_valid(_model):
		_model.rotate_y(delta * preview_spin_speed)

func _refresh() -> void:
	var sim = main.sim
	reserve_caption.text = "%d cr protected · %d cr available for drones" % [sim.reserve, maxi(0, int(sim.credits) - sim.reserve)]
	boost_button.disabled = sim.overdrive_cooldown > 0 or sim.victory
	if sim.overdrive > 0:
		boost_button.text = "BOOST ACTIVE · %ds" % ceili(sim.overdrive)
	elif sim.overdrive_cooldown > 0:
		boost_button.text = "BOOST · %ds" % ceili(sim.overdrive_cooldown)
	else:
		boost_button.text = "BOOST"
	if _page != null and _page.has_method("refresh"):
		_page.refresh()
