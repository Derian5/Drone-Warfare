@tool
class_name MapSite
extends Node3D
## A site on the battlefield: your base or an enemy target. Move it in the editor to
## change the map layout; the ground around it is drawn as a flat pad.

## Leave empty for the player's base and for build pads.
@export var data: TargetData
@export var is_player_base := false
## Reserve sites are hidden until the enemy deploys them (route adaptation).
@export var is_reserve := false

@export_group("Build pad")
## Neutral pad where the player can build a forward launch site.
@export var is_build_pad := false
@export var build_id := ""
@export var build_price := 350
## Shown after the pad is built (child node name). Hidden before.
@export var built_node: NodePath

@export_group("Base upgrades")
## Child shown when the player's base air defense is bought (level > 0).
@export var upgrade_node: NodePath

@export_group("Planet placement")
## On a planet map, sites are placed by map coordinates instead of their 3D position.
@export var use_map_coords := false
@export var map_coords := Vector2(50, 34)

@export_group("Outline")
@export var outline_size := Vector2(15, 11):
	set(value):
		outline_size = value
		_draw_outline()
@export var outline_angle := 0.0:
	set(value):
		outline_angle = value
		_draw_outline()
@export var outline_color := Color(0.76, 0.16, 0.18, 0.85):
	set(value):
		outline_color = value
		_draw_outline()
@export var outline_width := 0.22

@export_group("Damage")
## Smoke puffs per second at 100% damage.
@export var smoke_rate := 4.0
@export var smoke_area := Vector2(5, 4)
## Height the model is squashed to when destroyed (fraction).
@export_range(0.05, 1.0) var destroyed_scale := 0.3
## Optional child rotated slowly to "scan" (e.g. an AA turret).
@export var idle_rotate_node: NodePath
@export var idle_rotate_amount := 0.9

var _outline: MeshInstance3D
var _smoke := 0.0
var _time := 0.0
var _model: Node3D

func _ready() -> void:
	for child in get_children():
		if child is Node3D and child.name != "Outline":
			_model = child
			break
	_draw_outline()

func map_position() -> Vector2:
	if use_map_coords:
		return map_coords
	return Vector2(global_position.x, global_position.z)

func set_upgrade_level(level: int) -> void:
	var node = get_node_or_null(upgrade_node) as Node3D if not upgrade_node.is_empty() else null
	if node != null:
		node.visible = level > 0
		node.scale = Vector3.ONE * (1.0 + 0.15 * maxi(0, level - 1))

func set_built(built: bool) -> void:
	var node = get_node_or_null(built_node) as Node3D if not built_node.is_empty() else null
	if node != null:
		node.visible = built

func _draw_outline() -> void:
	if not is_inside_tree():
		return
	if _outline == null:
		_outline = MeshInstance3D.new()
		_outline.name = "Outline"
		_outline.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_outline, false, Node.INTERNAL_MODE_BACK)
	var corners = []
	for c in [Vector2(-1, -1), Vector2(1, -1), Vector2(1.1, 0.95), Vector2(-0.9, 1)]:
		corners.append((c * outline_size * 0.5).rotated(deg_to_rad(outline_angle)))
	var mesh = ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(corners.size()):
		var a: Vector2 = corners[i]
		var b: Vector2 = corners[(i + 1) % corners.size()]
		var side = (b - a).normalized().orthogonal() * outline_width * 0.5
		for p in [a - side, b - side, a + side, a + side, b - side, b + side]:
			mesh.surface_add_vertex(Vector3(p.x, 0.14, p.y))
	mesh.surface_end()
	_outline.mesh = mesh
	var material = StandardMaterial3D.new()
	material.albedo_color = outline_color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_outline.material_override = material

## Called every frame by the battlefield with the simulated state.
func show_state(hp_fraction: float, destroyed: bool, delta: float, spawn_smoke: Callable) -> void:
	_time += delta
	if _model != null:
		var target = destroyed_scale if destroyed else 1.0
		_model.scale.y = lerpf(_model.scale.y, target, minf(1.0, delta * 5.0)) if delta > 0 else target
	var turret = get_node_or_null(idle_rotate_node) as Node3D if not idle_rotate_node.is_empty() else null
	if turret != null and not destroyed:
		turret.rotation.y = sin(_time * 0.4) * idle_rotate_amount
	var damage = 1.0 - hp_fraction
	if delta > 0 and visible and (destroyed or damage > 0.35):
		_smoke += delta * smoke_rate * (1.25 if destroyed else damage)
		while _smoke > 1.0:
			_smoke -= 1.0
			var offset = Vector2(randf_range(-0.5, 0.5) * smoke_area.x, randf_range(-0.5, 0.5) * smoke_area.y)
			spawn_smoke.call(global_position + Vector3(offset.x, 2.0, offset.y))
