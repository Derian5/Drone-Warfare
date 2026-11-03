@tool
class_name FxSprite
extends Sprite3D
## Billboard sprite that grows, drifts and fades, then frees itself.

@export var life := 0.5
@export var size_from := 0.02
@export var size_to := 0.07
@export var velocity := Vector3.ZERO
## Random spread added to velocity on spawn.
@export var velocity_jitter := Vector3.ZERO
@export var start_delay := 0.0
@export var free_parent_when_done := false

var _age := 0.0
var _alpha := 1.0
var target_position = null   # Vector3: if set, the sprite travels to it over its life
var _start := Vector3.ZERO

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	_alpha = modulate.a
	_start = position
	velocity += Vector3(randf_range(-1, 1) * velocity_jitter.x, randf_range(-1, 1) * velocity_jitter.y, randf_range(-1, 1) * velocity_jitter.z)
	pixel_size = size_from
	visible = start_delay <= 0

func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if start_delay > 0:
		start_delay -= delta
		visible = start_delay <= 0
		return
	_age += delta
	var t = clampf(_age / maxf(life, 0.001), 0.0, 1.0)
	pixel_size = lerpf(size_from, size_to, 1.0 - pow(1.0 - t, 2.0))
	if target_position != null:
		position = _start.lerp(target_position, t)
	else:
		position += velocity * delta
	var c = modulate
	c.a = _alpha * (1.0 - t * t)
	modulate = c
	if t >= 1.0:
		if free_parent_when_done and get_parent() != null and get_parent().get_child_count() <= 1:
			get_parent().queue_free()
		else:
			queue_free()
