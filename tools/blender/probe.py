import bpy
import json

print(json.dumps({
    "blender_version": bpy.app.version_string,
    "active_scene": bpy.context.scene.name,
    "scenes": [scene.name for scene in bpy.data.scenes],
    "gltf_options": [p.identifier for p in bpy.ops.export_scene.gltf.get_rna_type().properties if p.identifier in ["filepath", "export_format", "use_selection", "export_materials", "export_texcoords", "export_normals", "export_yup", "export_apply", "export_image_format"]],
}, ensure_ascii=False))
