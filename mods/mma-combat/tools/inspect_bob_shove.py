import os
import sys
from pathlib import Path

import bpy

sys.path.append(str(Path(os.environ["TEMP"]) / "blender-mma-addon"))
import io_directx_x

io_directx_x.register()
bpy.ops.import_scene.directx_x(
    filepath=sys.argv[sys.argv.index("--") + 1], import_animation=True,
    import_textures=False, use_import_collection=False,
)
armature = next(obj for obj in bpy.context.scene.objects if obj.type == "ARMATURE")
print("ACTION", armature.animation_data.action.name if armature.animation_data else None)
print("RANGE", armature.animation_data.action.frame_range[:] if armature.animation_data else None)
print("BONES", [bone.name for bone in armature.pose.bones])
bpy.ops.wm.save_as_mainfile(filepath=sys.argv[sys.argv.index("--") + 2])
