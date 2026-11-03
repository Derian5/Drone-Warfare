class_name HunterMarker
extends Control
## Marker drawn over an incoming hunter drone (ui/map/hunter_marker.tscn):
## pulsing tap ring, HP arc and a "TAP!" tag. When the hunter is outside the map view
## it turns into an arrow on the screen edge. Colors and sizes are editable exports.

@export var ring_color := Color(0.95, 0.27, 0.22)
@export var crippled_color := Color(1.0, 0.72, 0.18)
@export var hp_color := Color(1, 1, 1, 0.95)
@export var ring_radius := 26.0
@export var pulse_amount := 6.0
@export var edge_margin := 26.0
@export var arrow_size := 16.0

@onready var tag: Label = %Tag

var _offscreen := false
var _direction := Vector2.RIGHT
var _hp := 1.0
var _crippled := false

func show_hunter(screen: Vector2, view: Vector2, hunter: Dictionary, crippled: bool) -> void:
	var rect = Rect2(Vector2.ONE * edge_margin, view - Vector2.ONE * edge_margin * 2)
	_offscreen = not rect.has_point(screen)
	_hp = clampf(hunter.hp / maxf(1.0, hunter.max_hp), 0, 1)
	_crippled = crippled
	if _offscreen:
		var center = view / 2
		_direction = (screen - center).normalized()
		position = Vector2(clampf(screen.x, rect.position.x, rect.end.x), clampf(screen.y, rect.position.y, rect.end.y))
	else:
		position = screen
	tag.text = "FINISH!" if crippled else "TAP!"
	tag.visible = not _offscreen
	tag.position = Vector2(-tag.size.x / 2, ring_radius + 4)
	queue_redraw()

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	var color = crippled_color if _crippled else ring_color
	var pulse = 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.01)
	if _offscreen:
		var tip = _direction * arrow_size
		var side = _direction.orthogonal() * arrow_size * 0.6
		draw_colored_polygon(PackedVector2Array([tip, -_direction * arrow_size * 0.4 + side, -_direction * arrow_size * 0.4 - side]), color)
		draw_circle(Vector2.ZERO, arrow_size * 0.35, Color(color, 0.5 + pulse * 0.5))
		return
	var r = ring_radius + pulse * pulse_amount
	draw_arc(Vector2.ZERO, r, 0, TAU, 40, Color(color, 0.85 - pulse * 0.4), 3.0, true)
	draw_arc(Vector2.ZERO, ring_radius - 6, -PI / 2, -PI / 2 + TAU * _hp, 32, hp_color, 4.0, true)
