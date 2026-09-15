import math
import os
import sys
from pathlib import Path

import bpy
from mathutils import Vector

toolkit_root = Path(os.environ.get("TEMP", "")) / "PZ_BlenderToolkit-v5.0.0PR2-inspect"
if toolkit_root.is_dir():
    sys.path.append(str(toolkit_root))
    try:
        import PZ_BlenderToolkit
        PZ_BlenderToolkit.register()
    except Exception:
        pass


args = sys.argv[sys.argv.index("--") + 1:]
blend_file = Path(args[0]).resolve()
output = Path(args[1]).resolve()
frame = int(args[2]) if len(args) > 2 else 22
bpy.ops.wm.open_mainfile(filepath=str(blend_file))
scene = bpy.context.scene
scene.frame_set(frame)
if bpy.context.object and bpy.context.object.mode != "OBJECT":
    bpy.ops.object.mode_set(mode="OBJECT")
for object_ in bpy.context.selected_objects:
    object_.select_set(False)
for obj in scene.objects:
    if obj.name == "Cube" or "Widget" in obj.name:
        obj.hide_render = True

points = []
for obj in scene.objects:
    if obj.type == "MESH" and not obj.hide_render:
        points.extend(obj.matrix_world @ Vector(corner) for corner in obj.bound_box)
minimum = Vector(tuple(min(point[i] for point in points) for i in range(3)))
maximum = Vector(tuple(max(point[i] for point in points) for i in range(3)))
center = (minimum + maximum) * 0.5
radius = max(maximum - minimum) * 0.75

bpy.ops.object.camera_add(location=center + Vector((radius * 1.6, -radius * 1.9, radius * 1.05)))
camera = bpy.context.object
direction = center - camera.location
camera.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
camera.data.lens = 52
scene.camera = camera
scene.render.engine = "BLENDER_WORKBENCH"
scene.display.shading.light = "STUDIO"
scene.display.shading.studio_light = "paint.sl"
scene.display.shading.color_type = "MATERIAL"
scene.render.resolution_x = 512
scene.render.resolution_y = 512
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = "PNG"
scene.render.filepath = str(output)
bpy.ops.render.render(write_still=True)
