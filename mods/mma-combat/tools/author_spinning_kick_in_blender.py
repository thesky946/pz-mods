"""Author a native Project Zomboid Bob spinning heel kick in Blender."""
import math
import os
import sys
from pathlib import Path

import bpy
from mathutils import Euler

sys.path.append(str(Path(os.environ["TEMP"]) / "blender-mma-addon"))
import io_directx_x


def args_after_separator():
    return [Path(value) for value in sys.argv[sys.argv.index("--") + 1:]]


def insert_rotation(bone, frame, base, delta=(0, 0, 0)):
    bone.rotation_mode = "QUATERNION"
    bone.rotation_quaternion = base @ Euler(delta, "XYZ").to_quaternion()
    bone.keyframe_insert(data_path="rotation_quaternion", frame=frame)


def main():
    source, destination = args_after_separator()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    io_directx_x.register()
    # The vanilla shove supplies an already-rigged guarded fighting stance.
    bpy.ops.import_scene.directx_x(filepath=str(source), import_animation=True,
                                   import_textures=False, set_frame_range=True,
                                   use_import_collection=False)
    armature = next(obj for obj in bpy.context.scene.objects if obj.type == "ARMATURE")
    bpy.context.view_layer.objects.active = armature
    armature.select_set(True)
    bpy.context.scene.frame_set(0)
    base = {bone.name: bone.rotation_quaternion.copy() for bone in armature.pose.bones}

    armature.animation_data_create()
    # The file overrides vanilla Bob_Shove.X, so its AnimationSet must retain
    # the vanilla action name or PZ will not resolve the clip.
    action = bpy.data.actions.new("Bob_Shove")
    armature.animation_data.action = action
    bpy.context.scene.frame_start = 1
    bpy.context.scene.frame_end = 40

    # Guard, load, blind turn, head-height heel contact, recoil, recovery.
    # The clip is authored directly on Bob so his bone rolls never twist.
    keys = {
        1:  {"Bip01": (0, 0, 0)},
        6:  {"Bip01": (0, math.radians(28), 0), "Bip01_Pelvis": (0, math.radians(14), 0), "Bip01_Spine": (0, math.radians(-18), 0), "Bip01_R_Thigh": (0, 0, math.radians(18)), "Bip01_R_Calf": (0, 0, math.radians(-28)), "Bip01_L_Thigh": (math.radians(-7), 0, 0)},
        12: {"Bip01": (0, math.radians(118), 0), "Bip01_Pelvis": (0, math.radians(32), 0), "Bip01_Spine": (0, math.radians(-42), 0), "Bip01_R_Thigh": (0, 0, math.radians(48)), "Bip01_R_Calf": (0, 0, math.radians(-65)), "Bip01_R_Foot": (0, 0, math.radians(12)), "Bip01_L_Thigh": (math.radians(-12), 0, 0), "Bip01_L_Calf": (math.radians(10), 0, 0)},
        17: {"Bip01": (0, math.radians(204), 0), "Bip01_Pelvis": (0, math.radians(30), 0), "Bip01_Spine": (0, math.radians(-14), 0), "Bip01_R_Thigh": (0, 0, math.radians(82)), "Bip01_R_Calf": (0, 0, math.radians(-18)), "Bip01_R_Foot": (0, 0, math.radians(16)), "Bip01_L_Thigh": (math.radians(-15), 0, 0), "Bip01_L_Calf": (math.radians(12), 0, 0)},
        23: {"Bip01": (0, math.radians(274), 0), "Bip01_Pelvis": (0, math.radians(12), 0), "Bip01_Spine": (0, 0, 0), "Bip01_R_Thigh": (0, 0, math.radians(44)), "Bip01_R_Calf": (0, 0, math.radians(-55)), "Bip01_R_Foot": (0, 0, math.radians(8)), "Bip01_L_Thigh": (math.radians(-5), 0, 0)},
        31: {"Bip01": (0, math.radians(336), 0), "Bip01_Pelvis": (0, math.radians(4), 0), "Bip01_Spine": (0, math.radians(5), 0), "Bip01_R_Thigh": (0, 0, math.radians(8)), "Bip01_R_Calf": (0, 0, math.radians(-12))},
        40: {"Bip01": (0, math.radians(360), 0)},
    }
    for frame, pose in keys.items():
        bpy.context.scene.frame_set(frame)
        for name, rotation in base.items():
            insert_rotation(armature.pose.bones[name], frame, rotation, pose.get(name, (0, 0, 0)))

    for curve in (fc for layer in action.layers for strip in layer.strips for bag in strip.channelbags for fc in bag.fcurves):
        for point in curve.keyframe_points:
            point.interpolation = "BEZIER"
        curve.update()
    bpy.context.scene.frame_set(1)
    blend_source = Path(__file__).resolve().parents[1] / "assets" / "Bob_Shove.blend"
    blend_source.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(blend_source))
    bpy.ops.export_scene.directx_x(filepath=str(destination), export_animation=True,
        export_armature=True, export_weights=True, pz_compat=True,
        anim_frame_start=1, anim_frame_end=40, anim_key_format="TRS",
        export_format="TEXT_X")


if __name__ == "__main__":
    main()
