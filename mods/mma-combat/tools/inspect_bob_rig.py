import os
import sys
from pathlib import Path
import bpy
sys.path.append(str(Path(os.environ["TEMP"]) / "blender-mma-addon"))
import io_directx_x

path = Path(sys.argv[sys.argv.index("--") + 1])
bpy.ops.wm.read_factory_settings(use_empty=True)
io_directx_x.register()
bpy.ops.import_scene.directx_x(filepath=str(path), import_animation=False, import_textures=False, use_import_collection=False)
rig = next(o for o in bpy.context.scene.objects if o.type == "ARMATURE")
for name in ("Dummy01", "Bip01", "Bip01_Pelvis"):
    bone = rig.data.bones.get(name)
    print(name, "parent", bone.parent.name if bone and bone.parent else None,
          "restquat", tuple(round(v, 5) for v in bone.matrix_local.to_quaternion()) if bone else None)
