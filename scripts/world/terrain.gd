@tool
class_name MapTerrain
extends MeshInstance3D
## Terrain built from a grayscale height map PNG. Paint textures/regions/<region>/*.png in any image
## editor; the look (colors, contour lines, grid) is set in the material.

@export var height_map: Texture2D:
	set(value):
		height_map = value
		_rebuild()
## World height of a white pixel.
@export var height_scale := 6.0:
	set(value):
		height_scale = value
		_rebuild()
## World X/Z of the top-left corner of the height map.
@export var world_origin := Vector2(-44, -40):
	set(value):
		world_origin = value
		_rebuild()
## World size covered by the height map (X, Z).
@export var world_size := Vector2(188, 148):
	set(value):
		world_size = value
		_rebuild()
## Mesh grid spacing in world units. Smaller = smoother hills, more vertices.
@export_range(0.25, 4.0) var mesh_step := 0.8:
	set(value):
		mesh_step = value
		_rebuild()

var _image: Image
var _w := 0
var _h := 0

func _ready() -> void:
	_rebuild()

func _rebuild() -> void:
	if not is_inside_tree() or height_map == null:
		return
	_image = height_map.get_image()
	if _image == null:
		return
	if _image.is_compressed():
		_image.decompress()
	_image.convert(Image.FORMAT_RF)
	_w = _image.get_width()
	_h = _image.get_height()
	var cols = int(world_size.x / mesh_step) + 1
	var rows = int(world_size.y / mesh_step) + 1
	var vertices = PackedVector3Array()
	var uvs = PackedVector2Array()
	var indices = PackedInt32Array()
	for j in range(rows):
		for i in range(cols):
			var uv = Vector2(float(i) / (cols - 1), float(j) / (rows - 1))
			var p = world_origin + uv * world_size
			vertices.append(Vector3(p.x, height_at(p), p.y))
			uvs.append(uv)
	for j in range(rows - 1):
		for i in range(cols - 1):
			var a = j * cols + i
			indices.append_array(PackedInt32Array([a, a + 1, a + cols, a + 1, a + cols + 1, a + cols]))
	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var built = ArrayMesh.new()
	built.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh = built
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var shader_material = material_override as ShaderMaterial
	if shader_material != null:
		shader_material.set_shader_parameter("height_map", height_map)
		shader_material.set_shader_parameter("height_scale", height_scale)
		shader_material.set_shader_parameter("texel", Vector2(1.0 / _w, 1.0 / _h))
		shader_material.set_shader_parameter("world_step", world_size.x / _w)
		shader_material.set_shader_parameter("world_origin", world_origin)
		shader_material.set_shader_parameter("world_size", world_size)

## Bilinear height at a map position. Used by gameplay (drone altitude, picking).
func height_at(p: Vector2) -> float:
	if _image == null:
		return 0.0
	var g = (p - world_origin) / world_size * Vector2(_w - 1, _h - 1)
	var x = clampf(g.x, 0, _w - 1.001)
	var y = clampf(g.y, 0, _h - 1.001)
	var x0 = int(x)
	var y0 = int(y)
	var fx = x - x0
	var fy = y - y0
	var a = _image.get_pixel(x0, y0).r
	var b = _image.get_pixel(x0 + 1, y0).r
	var c = _image.get_pixel(x0, y0 + 1).r
	var d = _image.get_pixel(x0 + 1, y0 + 1).r
	return lerpf(lerpf(a, b, fx), lerpf(c, d, fx), fy) * height_scale

## World position of a map point (used by everything that sits on the map).
func to_world(p: Vector2, lift: float = 0.0) -> Vector3:
	return Vector3(p.x, height_at(p) + lift, p.y)

func up_at(_p: Vector2) -> Vector3:
	return Vector3.UP

## Map point under a camera ray.
func pick(origin: Vector3, direction: Vector3) -> Vector2:
	if absf(direction.y) < 0.001:
		return Vector2(-100, -100)
	var point = origin + direction * (-origin.y / direction.y)
	for i in range(6):
		point = origin + direction * ((height_at(Vector2(point.x, point.z)) - origin.y) / direction.y)
	return Vector2(point.x, point.z)

func max_height() -> float:
	var top = 0.0
	if _image == null:
		return top
	for y in range(0, _h, 4):
		for x in range(0, _w, 4):
			top = maxf(top, _image.get_pixel(x, y).r)
	return top * height_scale
