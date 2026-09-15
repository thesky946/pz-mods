import os
import sys
from pathlib import Path

import bpy
from mathutils import Euler

sys.path.append(str(Path(os.environ["TEMP"]) / "blender-mma-addon"))
import io_directx_x

source, outdir = map(Path, sys.argv[sys.argv.index("--") + 1:])
io_directx_x.register()
bpy.ops.import_scene.directx_x(filepath=str(source), import_animation=True, import_textures=False, use_import_collection=False)
arm = next(o for o in bpy.context.scene.objects if o.type == "ARMATURE")
bpy.context.scene.frame_set(0)
base = {p.name: p.rotation_quaternion.copy() for p in arm.pose.bones}
for name, axis in (("x", (1,0,0)), ("y", (0,1,0)), ("z", (0,0,1))):
    for p in arm.pose.bones:
        p.rotation_mode = "QUATERNION"; p.rotation_quaternion = base[p.name]
    p = arm.pose.bones["Bip01_R_Thigh"]
    p.rotation_quaternion = base[p.name] @ Euler(tuple(v * 1.4 for v in axis), "XYZ").to_quaternion()
    p = arm.pose.bones["Bip01_R_Calf"]
    p.rotation_quaternion = base[p.name] @ Euler(tuple(v * -0.6 for v in axis), "XYZ").to_quaternion()
    bpy.context.view_layer.update()
    for obj in bpy.context.scene.objects:
        if obj.name == "Cube": obj.hide_render=True
    # camera front-ish
    bpy.ops.object.camera_add(location=(1.5,-2.0,1.15))
    c=bpy.context.object; c.rotation_euler=((arm.location-c.location).to_track_quat('-Z','Y').to_euler()); bpy.context.scene.camera=c
    sc=bpy.context.scene; sc.render.engine='BLENDER_WORKBENCH';sc.render.resolution_x=384;sc.render.resolution_y=384;sc.render.resolution_percentage=100;sc.render.image_settings.file_format='PNG';sc.render.filepath=str(outdir / f'axis-{name}.png');bpy.ops.render.render(write_still=True)
    bpy.data.objects.remove(c,do_unlink=True)
