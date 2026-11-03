extends VBoxContainer
## Forward base page: upgrades and totals (ui/hud/intel_base_page.tscn).

@export var panel_title := "YOUR BASE"

var main: Node

func setup(game: Node, _id: Variant) -> void:
	main = game
	%FrameButton.pressed.connect(func(): main.sfx.play("click"); main.upgrade("frame"))
	%DefenseButton.pressed.connect(func(): main.sfx.play("click"); main.upgrade("base_defense"))
	%FactoryButton.pressed.connect(func(): main.sfx.play("click"); main.upgrade("factory"))
	refresh()

func refresh() -> void:
	var sim = main.sim
	var b: GameBalance = sim.balance
	%FrameTile.set_value("%d SLOTS" % b.slots(sim.frame_level))
	%FactoryTile.set_value("LVL %d" % sim.factory_level)
	%DefenseTile.set_value("LVL %d" % sim.base_defense_level if sim.base_defense_level > 0 else "NONE")
	var frame_price = sim.upgrade_price("frame")
	%FrameButton.text = "Frame +1 slot · %d cr" % frame_price if frame_price >= 0 else "Frame fully upgraded"
	%FrameButton.disabled = frame_price < 0 or sim.credits < frame_price
	var factory_price = sim.upgrade_price("factory")
	%FactoryButton.text = "Assembly -%d%% time · %d cr" % [roundi((1.0 - b.factory_time_multiplier) * 100), factory_price] if factory_price >= 0 else "Assembly fully upgraded"
	%FactoryButton.disabled = factory_price < 0 or sim.credits < factory_price
	var defense_price = sim.upgrade_price("base_defense")
	%DefenseButton.text = ("Base air defense lvl %d · %d cr" % [sim.base_defense_level + 1, defense_price]) if defense_price >= 0 else "Base air defense maxed"
	%DefenseButton.disabled = defense_price < 0 or sim.credits < defense_price
	%Stolen.set_value("%d cr" % int(sim.totals.get("stolen", 0)))
	%Launched.set_value(str(int(sim.totals.launched)))
	%Hits.set_value(str(int(sim.totals.hit)))
	%Misses.set_value(str(int(sim.totals.get("miss", 0))))
	%Losses.set_value(str(int(sim.totals.lost)))
	%Income.set_value("%d cr" % int(sim.totals.income))
	%Spent.set_value("%d cr" % int(sim.totals.spent))
