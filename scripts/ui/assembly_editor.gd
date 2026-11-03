class_name AssemblyEditor
extends Control
## "New assembly line" window (ui/editor/assembly_editor.tscn).
## 1. pick a frame  2. pick modules (grouped by category, only those that fit the frame)
## 3. read the result. Hovering a frame or module explains why you would take it.

@export var tile_scene: PackedScene
@export var frame_card_scene: PackedScene
@export var preview_spin_speed := 0.4
@export var preview_lift := 0.55
@export var valid_text := "Valid build. Paid orders keep their old build."
@export var mass_ok_color := Color("3cc46a")
@export var mass_over_color := Color("d9353b")
## Group titles in the module list (ModuleData.Category order).
@export var category_titles: PackedStringArray = ["WARHEAD · pick one", "PROTECTION", "MOBILITY", "ELECTRONICS", "PAYLOAD"]
@export var catalog_columns := 3

@onready var title: Label = %Title
@onready var name_edit: LineEdit = %NameEdit
@onready var groups: VBoxContainer = %Groups
@onready var frames_row: HBoxContainer = %Frames
@onready var drone_holder: Node3D = %DroneHolder
@onready var preview_viewport: SubViewport = %PreviewViewport
@onready var preview_camera: Camera3D = %PreviewCamera
@onready var callouts: Callouts = %Callouts
@onready var stats_box: VBoxContainer = %Stats
@onready var mass_value: Label = %MassValue
@onready var mass_bar: ProgressBar = %MassBar
@onready var slots_label: Label = %Slots
@onready var error_label: Label = %Error
@onready var cost_value: Label = %CostValue
@onready var time_value: Label = %TimeValue
@onready var create_button: Button = %Create

var main: Node
var line_id := -1
var build: Dictionary = {}
var hover := ""
var hover_frame := ""
var _tiles := {}
var _cards := {}
var _group_boxes := {}
var _drone: DroneView
var _drone_frame := ""
var _time := 0.0

func setup(game: Node) -> void:
	main = game
	visible = false
	%Close.pressed.connect(close)
	%Cancel.pressed.connect(func(): main.sfx.play("click"); close())
	create_button.pressed.connect(_apply)
	callouts.camera = preview_camera
	callouts.viewport = preview_viewport
	for frame in main.balance.frames:
		var card = frame_card_scene.instantiate() as FrameCard
		frames_row.add_child(card)
		card.setup(frame)
		card.pressed.connect(_choose_frame.bind(frame.id))
		card.hovered.connect(func(id, inside):
			hover_frame = id if inside else ("" if hover_frame == id else hover_frame)
			_refresh_info()
		)
		_cards[frame.id] = card
	for c in range(category_titles.size()):
		var box = VBoxContainer.new()
		box.add_theme_constant_override("separation", 4)
		var caption = Label.new()
		caption.text = category_titles[c]
		caption.theme_type_variation = &"SectionTitle"
		box.add_child(caption)
		var grid = GridContainer.new()
		grid.columns = catalog_columns
		grid.add_theme_constant_override("h_separation", 6)
		grid.add_theme_constant_override("v_separation", 6)
		box.add_child(grid)
		groups.add_child(box)
		_group_boxes[c] = {"box": box, "grid": grid}
	for module in main.balance.modules:
		var tile = tile_scene.instantiate() as ModuleTile
		_group_boxes[int(module.category)].grid.add_child(tile)
		tile.setup(module)
		tile.pressed.connect(_choose.bind(module.id))
		tile.hovered.connect(func(id, inside):
			hover = id if inside else ("" if hover == id else hover)
			_refresh()
		)
		_tiles[module.id] = tile

func open(id: int) -> void:
	var sim = main.sim
	line_id = id
	if id >= 0:
		build = sim.line(id).build.duplicate(true)
		name_edit.text = sim.line(id).name
	else:
		var frames = sim.available_frames()
		build = {"frame": frames.back() if not frames.is_empty() else "", "warhead": main.balance.default_build_warhead, "modules": Array(main.balance.default_build_modules)}
		name_edit.text = "Striker %02d" % sim.next_line
	if not build.has("modules"):
		build.modules = []
	build.frame = main.balance.build_frame(build)
	_drop_misfits()
	title.text = "EDIT DRONE LINE" if id >= 0 else "NEW DRONE LINE"
	create_button.text = "SAVE CHANGES" if id >= 0 else "CREATE LINE"
	hover = ""
	hover_frame = ""
	show()
	preview_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_refresh()

func close() -> void:
	hide()
	preview_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED

## Removes modules the current frame cannot carry (after switching frames).
func _drop_misfits() -> void:
	var b: GameBalance = main.balance
	build.modules = build.modules.filter(func(m): return b.fits(m, build.frame))
	if not b.fits(build.warhead, build.frame):
		build.warhead = b.default_build_warhead
	while build.modules.size() > b.slots(main.sim.frame_level, build.frame):
		build.modules.pop_back()

func _toggled(source: Dictionary, id: String) -> Dictionary:
	var result = source.duplicate(true)
	var module = main.balance.module(id)
	if module.kind == ModuleData.Kind.WARHEAD:
		result.warhead = id
	elif result.modules.has(id):
		result.modules.erase(id)
	else:
		result.modules.append(id)
	return result

func _choose_frame(id: String) -> void:
	main.sfx.play("click")
	build.frame = id
	_drop_misfits()
	_refresh()

func _choose(id: String) -> void:
	var sim = main.sim
	if not sim.unlocked.has(id):
		if not sim.unlock(id):
			_refresh()
			error_label.text = "Not enough credits: unlocking costs %d cr, you have %d cr." % [main.balance.module(id).unlock_cost, int(sim.credits)]
			main.sfx.play("error")
			return
		main.sfx.play("coin")
		main.checkpoint()
	else:
		main.sfx.play("click")
	var next = _toggled(build, id)
	if next.modules.size() > main.balance.slots(sim.frame_level, build.frame):
		error_label.text = "All %d utility slots are full. Remove a module first (click an installed one)." % main.balance.slots(sim.frame_level, build.frame)
		error_label.theme_type_variation = &"ErrorText"
		main.sfx.play("error")
		return
	build = next
	_refresh()

func _region_for_frame(id: String) -> String:
	var campaign: CampaignData = main.campaign
	for region in campaign.regions:
		for frame in region.new_frames:
			if frame != null and frame.id == id:
				return "Unlocks in %s" % region.display_name
	return "Locked"

func _refresh() -> void:
	var sim = main.sim
	var b: GameBalance = main.balance
	var mods = sim.tech_mods()
	var stats = b.stats(build, sim.frame_level, sim.factory_level, mods)
	var preview = stats
	if not hover.is_empty() and sim.unlocked.has(hover) and b.fits(hover, build.frame):
		preview = b.stats(_toggled(build, hover), sim.frame_level, sim.factory_level, mods)
	var frames = sim.available_frames()
	var error = b.build_error(build, sim.unlocked, sim.frame_level, frames)
	var max_mass = b.max_mass(sim.frame_level, build.frame)
	for id in _cards:
		_cards[id].refresh(build.frame == id, frames.has(id), _region_for_frame(id))
	var available = sim.available_modules()
	var group_used = {}
	for id in _tiles:
		var module: ModuleData = b.module(id)
		var shown = (available.has(id) or sim.unlocked.has(id)) and b.fits(id, build.frame)
		_tiles[id].visible = shown
		if shown:
			group_used[int(module.category)] = true
		_tiles[id].refresh(build.warhead == id or build.modules.has(id), sim.unlocked.has(id), sim.credits)
	for c in _group_boxes:
		_group_boxes[c].box.visible = group_used.has(c)
	for bar in stats_box.get_children():
		if bar is StatBar:
			bar.show_values(float(stats.get(bar.stat_key, 0)), float(preview.get(bar.stat_key, 0)))
	mass_value.text = "%d / %d" % [stats.mass, max_mass]
	mass_bar.max_value = max_mass
	mass_bar.value = mini(stats.mass, max_mass)
	LineRow._tint(mass_bar, mass_over_color if stats.mass > max_mass else mass_ok_color)
	var pips = ""
	for i in range(b.slots(sim.frame_level, build.frame)):
		pips += "[x] " if i < build.modules.size() else "[ ] "
	slots_label.text = "UTILITY SLOTS  " + pips
	error_label.text = error if not error.is_empty() else valid_text
	error_label.theme_type_variation = &"ErrorText" if not error.is_empty() else &"HintText"
	cost_value.text = "%d cr" % stats.cost
	time_value.text = "%.1fs · %d cr/min" % [stats.interval, roundi(stats.cost * 60 / stats.interval)]
	create_button.disabled = not error.is_empty()
	_refresh_info()
	_rebuild_preview()

## The explanation box under the preview: hovered module, hovered frame, or the current frame.
func _refresh_info() -> void:
	var sim = main.sim
	var b: GameBalance = main.balance
	for child in %InfoEffects.get_children():
		child.queue_free()
	var effects: Array = []
	if not hover.is_empty():
		var module: ModuleData = b.module(hover)
		%InfoName.text = module.display_name
		%InfoTag.visible = not module.frames.is_empty()
		%InfoTag.text = " %s ONLY " % ", ".join(Array(module.frames)).to_upper()
		%InfoPurpose.text = module.purpose if not module.purpose.is_empty() else module.description
		effects = Array(module.effects())
		effects.append("mass %d" % module.mass)
		effects.append("+%d cr per drone" % module.cost_per_drone)
		var installed = build.warhead == hover or build.modules.has(hover)
		if not sim.unlocked.has(hover):
			%InfoAction.text = "Click to unlock for %d cr (once, for all lines)." % module.unlock_cost
		elif installed:
			%InfoAction.text = "Installed — click to remove." if module.kind == ModuleData.Kind.UTILITY else "Installed warhead."
		else:
			%InfoAction.text = "Click to install." if module.kind == ModuleData.Kind.UTILITY else "Click to switch to this warhead."
	else:
		var frame: FrameData = b.frame(hover_frame if not hover_frame.is_empty() else build.frame)
		%InfoName.text = frame.display_name
		%InfoTag.visible = true
		%InfoTag.text = " FRAME "
		%InfoPurpose.text = frame.description
		effects = ["%d HP" % frame.hp, "speed %d" % frame.speed, "agility %d" % frame.agility, "range %d" % frame.flight_range, "%d slots" % b.slots(sim.frame_level, frame.id), "%d cr base" % frame.cost]
		var available = sim.available_frames().has(frame.id)
		%InfoAction.text = ("Selected frame. Pick modules on the left." if frame.id == build.frame else "Click to switch frame. Modules that do not fit are removed.") if available else _region_for_frame(frame.id) + "."
	for text in effects:
		var label = Label.new()
		label.text = text
		var bad = text.begins_with("−") or text.begins_with("weak")
		var good = (text.begins_with("+") and not text.ends_with("per drone")) or text.begins_with("enemy accuracy") or text.begins_with("immune") or text.contains("decoy") or text.begins_with("×")
		label.theme_type_variation = &"EffectBad" if bad else (&"EffectGood" if good else &"MutedSmall")
		%InfoEffects.add_child(label)

func _rebuild_preview() -> void:
	if is_instance_valid(_drone):
		_drone.queue_free()
	var frame: FrameData = main.balance.frame(build.frame)
	var scene = frame.drone_scene if frame != null and frame.drone_scene != null else main.world.modular_drone_scene
	_drone = scene.instantiate() as DroneView
	drone_holder.add_child(_drone)
	var anchors = _drone.apply_build(build, main.balance)
	_drone.position.y = preview_lift
	_drone.rotation.y = -0.6 + sin(_time * preview_spin_speed) * 0.5
	callouts.items.clear()
	for id in [build.warhead] + build.modules:
		var module = main.balance.module(id)
		if module and anchors.has(id):
			callouts.items.append({"label": module.callout if not module.callout.is_empty() else module.short_name, "node": anchors[id]})

func _process(delta: float) -> void:
	if not visible:
		return
	_time += delta
	if is_instance_valid(_drone):
		_drone.rotation.y = -0.6 + sin(_time * preview_spin_speed) * 0.5
		_drone.spin(delta * 0.5)

func _apply() -> void:
	var sim = main.sim
	var success = false
	if line_id < 0:
		success = sim.create_line(name_edit.text, build) >= 0
	else:
		success = sim.update_build(line_id, name_edit.text, build)
	if success:
		main.sfx.play("coin")
		close()
		if line_id < 0:
			main.select("line", int(sim.lines.back().id))
		main.committed()
	else:
		error_label.text = "Could not apply the build. Check slots, mass and the line limit."
