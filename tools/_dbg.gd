extends SceneTree
func _initialize():
	for p in ["res://models/drones/drone_modular.glb", "res://models/modules/armor.glb"]:
		var n = load(p).instantiate()
		_walk(n, 0)
	quit()
func _walk(n, d):
	var extra = ""
	if n is MeshInstance3D:
		var m = n.mesh
		extra = " %s aabb=%s mat=%s" % [m.get_class(), m.get_aabb(), m.surface_get_material(0).albedo_color if m.surface_get_material(0) is StandardMaterial3D else m.surface_get_material(0)]
	print("  ".repeat(d), n.name, " ", n.get_class(), " pos=", n.position if n is Node3D else "", extra)
	for c in n.get_children(): _walk(c, d+1)
