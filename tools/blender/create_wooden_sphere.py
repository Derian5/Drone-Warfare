"""Run INSIDE the open Blender through tools/blender/mcp_client.py.

Creates a separate studio scene, bakes procedural wood to real PNG textures,
exports selected mesh to a self-contained GLB, writes a clean .blend source.
Does not delete objects or overwrite an existing exported model.
"""

import bpy
import json
import math
from pathlib import Path
from mathutils import Vector

PROJECT = Path(r"C:\Users\derian\Documents\Drone Warfare")
ASSET = "wooden_sphere"
MODEL_DIR = PROJECT / "models" / ASSET
TEXTURE_DIR = MODEL_DIR / "textures"
SOURCE_DIR = PROJECT / "art_source" / ASSET
GLB_PATH = MODEL_DIR / f"{ASSET}.glb"
BLEND_PATH = SOURCE_DIR / f"{ASSET}.blend"
SIZE = 1024

if not (PROJECT / "project.godot").is_file() or not (PROJECT / "models").is_dir():
    raise RuntimeError("Expected existing Drone Warfare project and models directory")
if GLB_PATH.exists() or BLEND_PATH.exists():
    raise RuntimeError("Asset already exists. Change ASSET to a new name instead of overwriting it.")
TEXTURE_DIR.mkdir(parents=True, exist_ok=True)
SOURCE_DIR.mkdir(parents=True, exist_ok=True)

scene = bpy.data.scenes.new("WoodenSphere_Studio")
bpy.context.window.scene = scene
scene.unit_settings.system = "METRIC"
scene.unit_settings.scale_length = 1.0
scene.render.engine = "CYCLES"
scene.cycles.device = "CPU"
scene.cycles.samples = 8
scene.render.bake.margin = 16
scene.render.bake.use_clear = True
scene.render.bake.use_pass_direct = False
scene.render.bake.use_pass_indirect = False
scene.render.bake.use_pass_color = True
scene.render.bake.normal_space = "TANGENT"

bpy.ops.mesh.primitive_uv_sphere_add(segments=64, ring_count=32, radius=1.0, location=(0, 0, 1), calc_uvs=True)
sphere = bpy.context.object
sphere.name = "WoodenSphere"
sphere.data.name = "WoodenSphere_Mesh"
for face in sphere.data.polygons:
    face.use_smooth = True
if sphere.data.uv_layers.active is None:
    raise RuntimeError("Sphere needs a UV map before baking")

procedural = bpy.data.materials.new("Wood_Procedural_Source")
procedural.use_nodes = True
procedural.use_fake_user = True
nodes = procedural.node_tree.nodes
links = procedural.node_tree.links
nodes.clear()
output = nodes.new("ShaderNodeOutputMaterial")
output.location = (850, 120)
bsdf = nodes.new("ShaderNodeBsdfPrincipled")
bsdf.location = (580, 120)
bsdf.inputs["Roughness"].default_value = 0.58
bsdf.inputs["Metallic"].default_value = 0.0
links.new(bsdf.outputs["BSDF"], output.inputs["Surface"])
coordinates = nodes.new("ShaderNodeTexCoord")
coordinates.location = (-1000, 100)
center = nodes.new("ShaderNodeVectorMath")
center.operation = "SUBTRACT"
center.inputs[1].default_value = (0.5, 0.5, 0.5)
center.location = (-820, 100)
links.new(coordinates.outputs["Generated"], center.inputs[0])
stretch = nodes.new("ShaderNodeVectorMath")
stretch.operation = "MULTIPLY"
stretch.inputs[1].default_value = (2.0, 2.0, 0.35)
stretch.location = (-640, 100)
links.new(center.outputs["Vector"], stretch.inputs[0])
rings = nodes.new("ShaderNodeTexWave")
rings.label = "Growth rings / distorted wood grain"
rings.wave_type = "RINGS"
rings.rings_direction = "Z"
rings.inputs["Scale"].default_value = 5.0
rings.inputs["Distortion"].default_value = 3.2
rings.inputs["Detail"].default_value = 3.0
rings.inputs["Detail Scale"].default_value = 1.5
rings.location = (-440, 240)
links.new(stretch.outputs["Vector"], rings.inputs["Vector"])
fine = nodes.new("ShaderNodeTexNoise")
fine.inputs["Scale"].default_value = 48.0
fine.inputs["Detail"].default_value = 2.0
fine.inputs["Roughness"].default_value = 0.7
fine.location = (-440, -140)
links.new(stretch.outputs["Vector"], fine.inputs["Vector"])
grain = nodes.new("ShaderNodeMixRGB")
grain.blend_type = "MULTIPLY"
grain.inputs[0].default_value = 0.35
grain.location = (-170, 160)
links.new(rings.outputs["Fac"], grain.inputs[1])
links.new(fine.outputs["Fac"], grain.inputs[2])
ramp = nodes.new("ShaderNodeValToRGB")
ramp.location = (40, 200)
ramp.color_ramp.elements.remove(ramp.color_ramp.elements[1])
for i, (position, color) in enumerate([
    (0.0, (0.055, 0.018, 0.006, 1)),
    (0.25, (0.17, 0.062, 0.017, 1)),
    (0.55, (0.38, 0.19, 0.065, 1)),
    (1.0, (0.58, 0.34, 0.13, 1)),
]):
    element = ramp.color_ramp.elements[0] if i == 0 else ramp.color_ramp.elements.new(position)
    element.position = position
    element.color = color
links.new(grain.outputs["Color"], ramp.inputs["Fac"])
links.new(ramp.outputs["Color"], bsdf.inputs["Base Color"])
bump = nodes.new("ShaderNodeBump")
bump.location = (300, -130)
bump.inputs["Strength"].default_value = 0.22
bump.inputs["Distance"].default_value = 0.035
links.new(grain.outputs["Color"], bump.inputs["Height"])
links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
sphere.data.materials.append(procedural)

def bake_image(name, bake_type, color_space):
    image = bpy.data.images.new(name, width=SIZE, height=SIZE, alpha=False)
    image.colorspace_settings.name = color_space
    image.filepath_raw = str(TEXTURE_DIR / f"{name}.png")
    image.file_format = "PNG"
    texture = nodes.new("ShaderNodeTexImage")
    texture.name = "BakeTarget_" + name
    texture.label = "Baked " + bake_type
    texture.image = image
    texture.location = (0, -430 if bake_type == "DIFFUSE" else -700)
    nodes.active = texture
    for node in nodes:
        node.select = node == texture
    result = bpy.ops.object.bake(type=bake_type)
    if "FINISHED" not in result:
        raise RuntimeError(f"Bake failed: {name}")
    image.save()
    image.pack()
    print(f"BAKED {name}: {SIZE}x{SIZE}, {color_space}")
    return image

albedo = bake_image("wood_basecolor", "DIFFUSE", "sRGB")
normal_image = bake_image("wood_normal", "NORMAL", "Non-Color")

# glTF exports this image-based Principled material, not the procedural source.
material = bpy.data.materials.new("Wood_Baked_PBR")
material.use_nodes = True
pbr = material.node_tree.nodes.get("Principled BSDF")
pbr.inputs["Metallic"].default_value = 0.0
pbr.inputs["Roughness"].default_value = 0.58
albedo_node = material.node_tree.nodes.new("ShaderNodeTexImage")
albedo_node.name = "Wood_BaseColor_sRGB"
albedo_node.image = albedo
albedo_node.location = (-500, 180)
material.node_tree.links.new(albedo_node.outputs["Color"], pbr.inputs["Base Color"])
normal_node = material.node_tree.nodes.new("ShaderNodeTexImage")
normal_node.name = "Wood_Normal_NonColor"
normal_node.image = normal_image
normal_node.location = (-500, -160)
normal_map = material.node_tree.nodes.new("ShaderNodeNormalMap")
normal_map.location = (-230, -130)
normal_map.inputs["Strength"].default_value = 0.75
material.node_tree.links.new(normal_node.outputs["Color"], normal_map.inputs["Color"])
material.node_tree.links.new(normal_map.outputs["Normal"], pbr.inputs["Normal"])
sphere.data.materials.clear()
sphere.data.materials.append(material)
sphere["source_material"] = procedural.name
sphere["asset_pipeline"] = "Local Blender MCP -> UV bake -> Principled PBR -> selected GLB -> Godot"

bpy.context.view_layer.objects.active = sphere
bpy.ops.object.select_all(action="DESELECT")
sphere.select_set(True)
result = bpy.ops.export_scene.gltf(
    filepath=str(GLB_PATH), export_format="GLB", use_selection=True,
    export_materials="EXPORT", export_texcoords=True, export_normals=True,
    export_yup=True, export_apply=True, export_image_format="AUTO",
)
if "FINISHED" not in result:
    raise RuntimeError("GLB export failed")

# A small studio only in the source .blend, never in the exported asset.
bpy.ops.mesh.primitive_plane_add(size=8, location=(0, 0, -0.015))
floor = bpy.context.object
floor.name = "StudioFloor_NOT_EXPORTED"
floor_material = bpy.data.materials.new("StudioFloor")
floor_material.diffuse_color = (0.16, 0.17, 0.19, 1)
floor.data.materials.append(floor_material)
world = bpy.data.worlds.new("WoodStudioWorld")
world.use_nodes = True
world.node_tree.nodes["Background"].inputs[0].default_value = (0.12, 0.14, 0.18, 1)
scene.world = world
for name, location, power, size in [
    ("KeyLight", (3, -4, 5), 650, 4),
    ("FillLight", (-3, -1, 3), 350, 3),
]:
    data = bpy.data.lights.new(name, "AREA")
    data.energy = power
    data.shape = "DISK"
    data.size = size
    obj = bpy.data.objects.new(name, data)
    scene.collection.objects.link(obj)
    obj.location = location
    obj.rotation_euler = (Vector((0, 0, 1)) - obj.location).to_track_quat("-Z", "Y").to_euler()
camera_data = bpy.data.cameras.new("StudioCamera")
camera = bpy.data.objects.new("StudioCamera", camera_data)
scene.collection.objects.link(camera)
camera.location = (4, -6, 3.3)
camera.rotation_euler = (Vector((0, 0, 1)) - camera.location).to_track_quat("-Z", "Y").to_euler()
scene.camera = camera
scene.render.resolution_x = 800
scene.render.resolution_y = 800
scene.render.resolution_percentage = 100
bpy.ops.object.select_all(action="DESELECT")
sphere.select_set(True)
bpy.context.view_layer.objects.active = sphere
for screen in bpy.data.screens:
    for area in screen.areas:
        if area.type == "VIEW_3D":
            area.spaces.active.shading.type = "MATERIAL"
            area.spaces.active.region_3d.view_location = Vector((0, 0, 1))
            area.spaces.active.region_3d.view_distance = 4.5
            area.spaces.active.region_3d.view_rotation = Vector((4, -6, 3.3)).to_track_quat("Z", "Y")

# libraries.write saves a normal .blend containing only this new scene and its
# dependencies, without changing the filename of the user's open Blender file.
bpy.data.libraries.write(str(BLEND_PATH), {scene, procedural}, path_remap="RELATIVE_ALL", fake_user=True, compress=True)
sphere.data.calc_loop_triangles()
report = {
    "blender": bpy.app.version_string,
    "scene": scene.name,
    "object": sphere.name,
    "vertices": len(sphere.data.vertices),
    "triangles": len(sphere.data.loop_triangles),
    "uv_map": sphere.data.uv_layers.active.name,
    "radius_m": 1.0,
    "material": material.name,
    "textures": [str(TEXTURE_DIR / "wood_basecolor.png"), str(TEXTURE_DIR / "wood_normal.png")],
    "blend": str(BLEND_PATH),
    "glb": str(GLB_PATH),
    "glb_bytes": GLB_PATH.stat().st_size,
}
(MODEL_DIR / "pipeline_report.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
print(json.dumps(report, indent=2))
