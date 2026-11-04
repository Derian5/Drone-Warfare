extends Control
## Game controller (root of main.tscn). Owns the simulation and connects the scene parts:
## the current region scene (scenes/regions/*.tscn, listed in data/campaign.tres) and the UI panels (ui/**/*.tscn).
## Layout, look and texts live in those scenes; balance lives in data/balance.tres.

signal state_changed

const Simulation = preload("res://scripts/sim/simulation.gd")

@export var balance: GameBalance = preload("res://data/balance.tres")
@export var campaign: CampaignData = preload("res://data/campaign.tres")
## Zoom the camera starts at when a region opens (smaller = closer), then eases to 1.
@export var region_intro_zoom := 0.72
## Simulation step in seconds (fixed step keeps results deterministic).
@export var sim_step := 0.05
@export var autosave_interval := 8.0
@export var persistence_enabled := true

@onready var map_view: MapView = %MapView
var world: Battlefield
@onready var top_bar: TopBar = %TopBar
@onready var lines_panel: LinesPanel = %LinesPanel
@onready var intel: IntelPanel = %IntelPanel
@onready var toast: Toast = %Toast
@onready var victory_panel: VictoryPanel = %VictoryPanel
@onready var campaign_screen: CampaignScreen = %CampaignScreen
@onready var editor: AssemblyEditor = %AssemblyEditor
@onready var dev_panel: DevPanel = %DevPanel
@onready var guide_card: GuideCard = %GuideCard
@onready var sfx: Sfx = %Sfx
@onready var help_dialog: AcceptDialog = %HelpDialog
@onready var reset_dialog: ConfirmationDialog = %ResetDialog

var sim: RefCounted
var paused := false
var backgrounded := false
var muted := false
var selected := {"kind": "target", "id": ""}
var _accumulator := 0.0
var _ui_timer := 0.0
var _save_timer := 0.0
var _ledger: Array = []
var _ledger_timer := 0.0
var _last_pending := ""
var _last_victory := false
## Simulation speed multiplier (developer panel, debug builds only).
var time_scale := 1.0
## The player closed the tutorial steps (alerts still show).
var guide_dismissed := false

func _ready() -> void:
	get_window().min_size = Vector2i(1100, 640)
	sim = Simulation.new(balance, campaign)
	sim.notice.connect(notice)
	sim.effect.connect(_on_effect)
	var saved_region = Simulation.peek_region() if persistence_enabled else -1
	_load_region_scene(maxi(0, saved_region))
	sim.start_region(maxi(0, saved_region), world.layout())
	var restored = saved_region >= 0 and sim.load_game()
	world.setup(sim)
	_load_settings()
	map_view.setup(self)
	for part in [top_bar, guide_card, lines_panel, intel, toast, victory_panel, editor, campaign_screen, dev_panel]:
		part.setup(self)
	reset_dialog.confirmed.connect(_reset_run)
	select("target", main_target_id())
	_last_pending = sim.pending_adaptation
	_last_victory = sim.victory
	committed()
	notice("Save loaded. Welcome back, commander." if restored else "Free drones are already raiding the supply depot. Drag from your base to the enemy HQ to draw a route, then build your own line.")
	get_tree().auto_accept_quit = false
	if OS.has_feature("web"):
		JavaScriptBridge.eval("document.body.dataset.gameReady='true'; document.body.dataset.scene='3d';")

func _load_region_scene(index: int) -> void:
	if is_instance_valid(world):
		world.get_parent().remove_child(world)
		world.queue_free()
	var region: RegionData = campaign.regions[clampi(index, 0, campaign.regions.size() - 1)]
	world = region.scene.instantiate() as Battlefield
	map_view.viewport.add_child(world)
	world.zoom = region_intro_zoom
	world.zoom_target = 1.0

func main_target_id() -> String:
	return sim.main_target().get("id", "")

## Opens a region from the campaign screen (also used to replay).
func start_region(index: int) -> void:
	if not sim.region_unlocked(index):
		return
	map_view.set_draw_mode(false)
	_load_region_scene(index)
	sim.start_region(index, world.layout())
	world.setup(sim)
	map_view.attach_world(world)
	_ledger.clear()
	_last_victory = false
	_last_pending = ""
	select("target", main_target_id())
	committed()
	var region = sim.region_data
	var text = "%s — %s" % [region.display_name, region.subtitle] if region else "New region."
	if region and not region.new_frames.is_empty():
		text += " New frame: %s. Open + NEW DRONE LINE to try it." % ", ".join(region.new_frames.map(func(f): return f.display_name))
	notice(text)

# ---------------------------------------------------------------- shared actions (used by panels)

func select(kind: String, id: Variant) -> void:
	selected = {"kind": kind, "id": id}
	world.selected_route = int(id) if kind == "route" else -1
	world.selected_target = str(id) if kind == "target" else ("base" if kind == "base" else "")
	world.refresh_routes()
	intel.show_selection(kind, id)
	refresh()

func committed() -> void:
	lines_panel.rebuild()
	world.refresh_routes()
	intel.show_selection(selected.kind, selected.id)
	checkpoint()
	refresh()

func delete_selected_route() -> void:
	if selected.kind != "route":
		return
	delete_route(int(selected.id))

func delete_route(id: int) -> void:
	if sim.route(id).is_empty():
		return
	map_view.set_draw_mode(false)
	sim.delete_route(id)
	if selected.kind == "route" and int(selected.id) == id:
		select("target", main_target_id())
	committed()

func open_editor(line_id: int) -> void:
	if line_id < 0 and sim.paid_line_count() >= sim.line_slots:
		notice("All open line slots are in use. Open a new slot or edit an existing build.")
		return
	map_view.set_draw_mode(false)
	editor.open(line_id)

func toggle_line(line_id: int) -> void:
	var item = sim.line(line_id)
	if item.is_empty():
		return
	item.enabled = not item.enabled
	checkpoint()
	refresh()

func change_reserve(amount: int) -> void:
	sim.reserve = clampi(sim.reserve + amount, 0, 100000)
	checkpoint()
	refresh()

func boost() -> void:
	if sim.activate_overdrive():
		sfx.play("coin")
		checkpoint()
	refresh()

func upgrade(kind: String) -> void:
	if sim.upgrade(kind):
		sfx.play("coin")
		checkpoint()
	else:
		notice("Not enough credits, or the upgrade is already installed.")
	refresh()

func toggle_pause() -> void:
	paused = not paused
	refresh()

## Normal / double speed for everyone (the developer panel also offers ×3).
func toggle_speed() -> void:
	time_scale = 1.0 if time_scale > 1.0 else 2.0
	refresh()

func toggle_sound() -> void:
	muted = not muted
	sfx.muted = muted
	_save_settings()
	refresh()

func upgrade_line(id: int) -> void:
	if sim.upgrade_line(id):
		sfx.play("coin")
		checkpoint()
	refresh()

func buy_line_slot() -> void:
	if sim.buy_line_slot():
		sfx.play("coin")
		checkpoint()
	refresh()

func build_pad(id: String, building_id: String = "pad") -> void:
	if sim.build_pad(id, building_id):
		sfx.play("coin")
		checkpoint()
	refresh()

func buy_tech(id: String) -> void:
	if sim.buy_tech(id):
		sfx.play("coin")
		checkpoint()
	refresh()

func open_campaign() -> void:
	map_view.set_draw_mode(false)
	campaign_screen.open()

func next_region() -> void:
	var next = sim.region_index + 1
	if next < sim.region_count() and sim.region_unlocked(next):
		start_region(next)
	else:
		open_campaign()

func _reset_run() -> void:
	if persistence_enabled:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Simulation.SAVE_PATH))
	sim = Simulation.new(balance, campaign)
	sim.notice.connect(notice)
	sim.effect.connect(_on_effect)
	paused = false
	start_region(0)
	notice("New campaign. Drag from your base to the enemy HQ and build an assembly line.")

func net_per_minute() -> float:
	if _ledger.size() < 2:
		return 0.0
	var first = _ledger[0]
	var last = _ledger.back()
	return ((last[0] - first[0]) - (last[1] - first[1])) * 60.0 / maxf(_ledger.size() - 1, 20.0)

func objective() -> String:
	if sim.victory:
		return "%s CAPTURED" % (sim.region_data.display_name.to_upper() if sim.region_data else "REGION")
	var paid = sim.lines.filter(func(l): return not l.free)
	var main_id = main_target_id()
	var main = sim.main_target()
	if not sim.routes.any(func(r): return r.target == main_id) and paid.is_empty():
		return "Draw a route to %s" % main.get("name", "target")
	if paid.is_empty():
		return "Create an assembly line (top right)"
	var unassigned = paid.filter(func(l): return l.route < 0)
	if unassigned.size() == paid.size():
		return "Drag line L%d onto a route arrow" % unassigned[0].id
	var idle = paid.filter(func(l): return l.route >= 0 and not l.enabled)
	if idle.size() == paid.size():
		return "Press PLAY to start line L%d" % idle[0].id
	if not sim.pending_adaptation.is_empty():
		return "Enemy air defense is adapting — rethink your build"
	return "Destroy %s · %d%%" % [main.get("name", "target").trim_prefix("Enemy "), ceili(main.get("hp", 0.0) / maxf(1.0, main.get("max_hp", 1.0)) * 100)]

## The "what to do now" card in the right panel. Empty = nothing to show.
func guide() -> Dictionary:
	if sim.victory:
		return {}
	if not sim.hunters.is_empty():
		return {"kind": "alert", "kicker": "HUNTERS INCOMING", "title": "Click the red rings on the map", "body": "A hunter that reaches your base stops a line and steals 30% of your credits."}
	if not sim.pending_adaptation.is_empty():
		return {"kind": "info", "kicker": "ENEMY ADAPTING · %ds" % ceili(sim.adaptation_timer), "title": "Air defense is getting a counter", "body": "The enemy answers your most used module or route. Change a line's build (EDIT) or draw another route."}
	var paid = sim.lines.filter(func(l): return not l.free)
	var main_id = main_target_id()
	if not guide_dismissed:
		if not sim.routes.any(func(r): return r.target == main_id) and paid.is_empty():
			return {"kind": "step", "kicker": "NEXT STEP · 1 OF 4", "title": "Draw a route to the Enemy HQ", "body": "Press on your blue base and drag to the red Enemy HQ, then let go. Curve around the red rings — they shoot drones down."}
		if paid.is_empty():
			return {"kind": "step", "kicker": "NEXT STEP · 2 OF 4", "title": "Build a drone line", "body": "Press + NEW DRONE LINE below. Pick a frame, a warhead and modules, then press CREATE LINE."}
		if paid.all(func(l): return l.route < 0):
			return {"kind": "step", "kicker": "NEXT STEP · 3 OF 4", "title": "Send line L%d along a route" % paid[0].id, "body": "Drag the L%d row below onto a route arrow on the map — or click the row and pick the route from the list." % paid[0].id}
		if paid.all(func(l): return not l.enabled):
			return {"kind": "step", "kicker": "NEXT STEP · 4 OF 4", "title": "Start line L%d" % paid[0].id, "body": "Press START on the line. It builds a drone every few seconds and launches it along the route."}
	for item in paid:
		var info = sim.status_info(item)
		if info.level == "bad":
			return {"kind": "alert", "kicker": "L%d NEEDS HELP" % item.id, "title": info.text, "body": info.hint}
	return {}

func notice(text: String) -> void:
	if toast != null and sim != null:
		toast.notice(text, sim.pending_adaptation)

func checkpoint(explicit: bool = false) -> void:
	if not persistence_enabled:
		return
	if not sim.save_game():
		notice("Could not save progress. Check that browser storage is available.")
	elif explicit:
		notice("Progress saved.")

# ---------------------------------------------------------------- loop

func is_running() -> bool:
	return not paused and not backgrounded and not editor.visible and not help_dialog.visible and not reset_dialog.visible and not campaign_screen.visible

func _process(delta: float) -> void:
	if sim == null:
		return
	var running = is_running()
	if running:
		_accumulator += minf(delta, 0.25) * time_scale
		while _accumulator >= sim_step:
			sim.step(sim_step)
			_accumulator -= sim_step
		_ledger_timer += delta * time_scale
		if _ledger_timer >= 1.0:
			_ledger_timer = 0.0
			_ledger.append([sim.totals.income, sim.totals.spent])
			if _ledger.size() > 61:
				_ledger.pop_front()
	world.sync(delta * time_scale if running else 0.0)
	_ui_timer += delta
	_save_timer += delta
	if _ui_timer > 0.15:
		_ui_timer = 0
		refresh()
	if _save_timer > autosave_interval and running:
		_save_timer = 0
		checkpoint()

func refresh() -> void:
	if sim.pending_adaptation != _last_pending:
		if not sim.pending_adaptation.is_empty():
			sfx.play("warning")
		_last_pending = sim.pending_adaptation
	if sim.victory != _last_victory:
		_last_victory = sim.victory
		if sim.victory:
			sfx.play("victory")
			world.zoom_target = world.victory_zoom
			checkpoint()
	state_changed.emit()
	if OS.has_feature("web"):
		JavaScriptBridge.eval("document.body.dataset.gameTicks='%d'; document.body.dataset.drones='%d';" % [int(sim.elapsed * 20), sim.drones.size()])

func _on_effect(kind: String, _pos: Vector2) -> void:
	match kind:
		"hit":
			sfx.play("boom")
		"lost", "miss":
			sfx.play("pop")
		"launch":
			sfx.play("launch")
		"shot":
			sfx.play("shot")
		"hunters":
			sfx.play("warning")

# ---------------------------------------------------------------- input & settings

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			if editor.visible:
				editor.close()
			elif campaign_screen.visible:
				campaign_screen.close()
			elif map_view.is_busy():
				map_view.set_draw_mode(false)
			else:
				toggle_pause()
			get_viewport().set_input_as_handled()
		elif event.keycode in [KEY_DELETE, KEY_BACKSPACE] and selected.kind == "route" and not editor.visible:
			delete_selected_route()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_F and not editor.visible:
			toggle_speed()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_SPACE and not editor.visible:
			toggle_pause()
			get_viewport().set_input_as_handled()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		backgrounded = true
		if is_node_ready() and sim != null:
			checkpoint()
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		backgrounded = false
	elif what == NOTIFICATION_WM_CLOSE_REQUEST:
		if sim != null:
			checkpoint()
		get_tree().quit()

func _load_settings() -> void:
	var config = ConfigFile.new()
	if persistence_enabled and config.load("user://settings.cfg") == OK:
		muted = bool(config.get_value("audio", "muted", false))
	sfx.muted = muted

func _save_settings() -> void:
	if not persistence_enabled:
		return
	var config = ConfigFile.new()
	config.set_value("audio", "muted", muted)
	config.save("user://settings.cfg")
