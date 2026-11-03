extends VBoxContainer
## Neutral build pad: buy a forward launch site (ui/hud/intel_pad_page.tscn).

@export var panel_title := "BUILD SITE"
@export_multiline var info_text := "A forward launch pad lets you start routes closer to the enemy: shorter flights, less time under fire, and targets beyond the drones' range become reachable."

var main: Node
var id := ""

func setup(game: Node, pad_id: Variant) -> void:
	main = game
	id = str(pad_id)
	%Info.text = info_text
	%BuildButton.pressed.connect(func(): main.sfx.play("click"); main.build_pad(id))
	refresh()

func refresh() -> void:
	var sim = main.sim
	var site = sim.build_site(id)
	var built = sim.built_sites.has(id)
	%Name.text = "FORWARD LAUNCH PAD" if built else "EMPTY BUILD SITE"
	%BuildButton.visible = not built
	%BuildButton.text = "Build forward pad · %d cr" % site.get("price", 0)
	%BuildButton.disabled = sim.credits < site.get("price", 0)
	%Hint.text = "Drag from this pad to a target to draw a route." if built else ""
