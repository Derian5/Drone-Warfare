extends SceneTree

var failures = 0

func check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: " + description)
	else:
		failures += 1
		push_error(description)

func _initialize() -> void:
	call_deferred("verify")

func verify() -> void:
	var packed = load("res://models/wooden_sphere/wooden_sphere.glb") as PackedScene
	check(packed != null, "GLB imports as a PackedScene")
	if packed == null:
		quit(1)
		return
	var model = packed.instantiate()
	var meshes = model.find_children("*", "MeshInstance3D", true, false)
	if model is MeshInstance3D:
		meshes.append(model)
	check(meshes.size() == 1, "Only the sphere mesh is exported, no studio floor/lights/cameras")
	for mesh_node in meshes:
		var mesh: Mesh = mesh_node.mesh
		check(mesh != null and mesh.get_surface_count() == 1, "Sphere has one mesh surface")
		var material = mesh.surface_get_material(0) as BaseMaterial3D
		check(material != null, "Principled PBR material converted to Godot material")
		if material != null:
			check(material.albedo_texture != null, "Baked wood base color imported")
			check(material.normal_enabled and material.normal_texture != null, "Tangent-space normal texture imported")
			check(is_equal_approx(material.metallic, 0.0), "Wood is non-metallic")
			if material.albedo_texture != null:
				check(material.albedo_texture.get_width() == 1024 and material.albedo_texture.get_height() == 1024, "Base color resolution is 1024x1024")
		var arrays = mesh.surface_get_arrays(0)
		check(arrays[Mesh.ARRAY_TEX_UV].size() == arrays[Mesh.ARRAY_VERTEX].size(), "UVs imported for every render vertex")
		check(mesh.get_aabb().size.is_equal_approx(Vector3(2, 2, 2)), "Sphere diameter is 2 Godot units / meters")
	model.free()
	var main = load("res://scenes/previews/asset_preview.tscn") as PackedScene
	check(main != null, "asset_preview.tscn imports successfully")
	if main != null:
		# Do not add to SceneTree: no game execution, no player save access.
		var scene = main.instantiate()
		check(scene.has_node("Rocket"), "Existing user Rocket node is preserved")
		check(scene.has_node("WoodenSpherePreview/WoodenSphere"), "Imported sphere is an authored editor-visible main.tscn node")
		check(scene.get_node("WoodenSpherePreview").visible, "Sphere preview is visible in the editor")
		scene.free()
	print("WOOD IMPORT: %d failures" % failures)
	quit(0 if failures == 0 else 1)
