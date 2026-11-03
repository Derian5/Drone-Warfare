@tool
class_name PlanetTerrain
extends MeshInstance3D
## Planet-scale map: the 100 x 68 play area is wrapped onto the camera-facing side of a sphere.
## Paint the surface in textures/regions/05_orbit/*.png (equirectangular, whole planet).

@export var radius := 60.0:
	set(value):
		radius = value
		_rebuild()
## Longitude/latitude span (degrees) covered by the play area.
@export var longitude_span := 110.0
@export var latitude_span := 72.0
## Longitude/latitude of the play area centre (degrees).
@export var center_lon := 0.0
@export var center_lat := 8.0
@export var play_area := Vector2(100, 68)

func _ready() -> void:
	_rebuild()

func _rebuild() -> void:
	if not is_inside_tree():
		return
	var sphere = SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2
	sphere.radial_segments = 128
	sphere.rings = 64
	mesh = sphere

func _lon_lat(p: Vector2) -> Vector2:
	var lon = center_lon + (p.x / play_area.x - 0.5) * longitude_span
	var lat = center_lat + (0.5 - p.y / play_area.y) * latitude_span
	return Vector2(deg_to_rad(lon), deg_to_rad(lat))

func up_at(p: Vector2) -> Vector3:
	var ll = _lon_lat(p)
	return global_basis * Vector3(cos(ll.y) * sin(ll.x), sin(ll.y), cos(ll.y) * cos(ll.x))

func to_world(p: Vector2, lift: float = 0.0) -> Vector3:
	return global_position + up_at(p) * (radius + lift)

func height_at(_p: Vector2) -> float:
	return 0.0

func pick(origin: Vector3, direction: Vector3) -> Vector2:
	var oc = origin - global_position
	var b = oc.dot(direction)
	var c = oc.dot(oc) - radius * radius
	var h = b * b - c
	if h < 0:
		return Vector2(-100, -100)
	var hit = origin + direction * (-b - sqrt(h)) - global_position
	var local = (global_basis.inverse() * hit).normalized()
	var lon = rad_to_deg(atan2(local.x, local.z))
	var lat = rad_to_deg(asin(clampf(local.y, -1, 1)))
	return Vector2(((lon - center_lon) / longitude_span + 0.5) * play_area.x, (0.5 - (lat - center_lat) / latitude_span) * play_area.y)
