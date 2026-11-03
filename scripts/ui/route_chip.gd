class_name RouteChip
extends PanelContainer
## Route badge placed near the middle of each arrow (ui/map/route_chip.tscn).

@onready var badge: Panel = %Badge
@onready var number: Label = %Number
@onready var tokens_label: Label = %Tokens

signal delete_requested(id: int)

var route_id := -1

func _ready() -> void:
	%Delete.pressed.connect(func(): delete_requested.emit(route_id))

func show_route(at: Vector2, id: int, color: Color, tokens: Array, highlight: bool) -> void:
	route_id = id
	number.text = str(id)
	%Delete.visible = not tokens.has("FREE")
	%Delete.tooltip_text = "Delete route R%d (lines on it stop until you give them a new route)" % id
	badge.self_modulate = color
	tokens_label.text = " · ".join(tokens) if not tokens.is_empty() else "no lines"
	theme_type_variation = &"RouteChipSelected" if highlight else &"RouteChip"
	modulate.a = 1.0 if not tokens.is_empty() or highlight else 0.85
	reset_size()
	position = at
