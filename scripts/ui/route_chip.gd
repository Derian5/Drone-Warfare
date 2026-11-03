class_name RouteChip
extends PanelContainer
## Route badge placed near the middle of each arrow (ui/map/route_chip.tscn).

@onready var badge: Panel = %Badge
@onready var number: Label = %Number
@onready var tokens_label: Label = %Tokens

func show_route(at: Vector2, id: int, color: Color, tokens: Array, highlight: bool) -> void:
	number.text = str(id)
	badge.self_modulate = color
	tokens_label.text = " · ".join(tokens) if not tokens.is_empty() else "no lines"
	theme_type_variation = &"RouteChipSelected" if highlight else &"RouteChip"
	modulate.a = 1.0 if not tokens.is_empty() or highlight else 0.85
	reset_size()
	position = at
