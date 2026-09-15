"""Retarget a spinning heel-kick FBX to Project Zomboid Bob and export PZ X."""
import os
import sys
from pathlib import Path

import bpy
from mathutils import Matrix

sys.path.append(str(Path(os.environ["TEMP"]) / "blender-mma-addon"))
import io_directx_x


# Trim idle lead-in/tail: turn, heel contact, recovery.  29 PZ frames are
# approximately the configured 1.2 s Shove swing window at 4,800 TPS.
SOURCE_START = 20
SOURCE_END = 110
OUTPUT_END = 29

MAPPING = {
    "Bip01_Spine": "Spine1",
    "Bip01_Spine1": "Chest",
    "Bip01_Neck": "Neck1",
    "Bip01_Head": "Head",
    "Bip01_L_Clavicle": "LeftShoulder",
    "Bip01_L_UpperArm": "LeftArm",
    "Bip01_L_Forearm": "LeftForeArm",
    "Bip01_L_Hand": "LeftHand",
    "Bip01_R_Clavicle": "RightShoulder",
    "Bip01_R_UpperArm": "RightArm",
    "Bip01_R_Forearm": "RightForeArm",
    "Bip01_R_Hand": "RightHand",
    "Bip01_L_Thigh": "LeftLeg",
    "Bip01_L_Calf": "LeftShin",
    "Bip01_L_Foot": "LeftFoot",
    "Bip01_L_Toe0": "LeftToeBase",
    "Bip01_R_Thigh": "RightLeg",
    "Bip01_R_Calf": "RightShin",
    "Bip01_R_Foot": "RightFoot",
    "Bip01_R_Toe0": "RightToeBase",
}


def cli_paths():
    values = sys.argv[sys.argv.index("--") + 1:]
    return tuple(Path(value) for value in values)


def scale_action(action):
    factor = (OUTPUT_END - 1) / (SOURCE_END - SOURCE_START)
    curves = []
    for layer in action.layers:
        for strip in layer.strips:
            for channelbag in strip.channelbags:
                curves.extend(channelbag.fcurves)
    for curve in curves:
        for key in curve.keyframe_points:
            key.co.x = 1 + (key.co.x - SOURCE_START) * factor
            key.handle_left.x = 1 + (key.handle_left.x - SOURCE_START) * factor
            key.handle_right.x = 1 + (key.handle_right.x - SOURCE_START) * factor
        curve.update()


def main():
    bob_x, source_bvh, output_x, blend_path = cli_paths()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    io_directx_x.register()
    bpy.ops.import_scene.directx_x(filepath=str(bob_x), import_animation=False,
                                   import_textures=False, use_import_collection=False)
    target = next(obj for obj in bpy.context.scene.objects if obj.type == "ARMATURE")
    target.name = "Bob"
    bpy.context.view_layer.objects.active = target
    target.select_set(True)

    bpy.ops.import_scene.fbx(filepath=str(source_bvh))
    source = bpy.context.object
    source.name = "SpinningHeelKick_Source"
    bpy.context.scene.frame_set(1)
    source_root_rest = source.matrix_world.to_quaternion().copy()

    target.animation_data_create()
    target.animation_data.action = bpy.data.actions.new("Bob_Shove")
    for frame in range(1, OUTPUT_END + 1):
        source_frame = round(SOURCE_START + (SOURCE_END - SOURCE_START) * (frame - 1) / (OUTPUT_END - 1))
        bpy.context.scene.frame_set(source_frame)
        root = target.pose.bones["Bip01"]
        root.rotation_mode = "QUATERNION"
        root.rotation_quaternion = source_root_rest.inverted() @ source.matrix_world.to_quaternion()
        root.keyframe_insert(data_path="rotation_quaternion", frame=frame)
        # Global retarget: transform each animated source bone from its rest
        # frame into Bob's rest frame, then solve Bob's local basis from its
        # already-evaluated parent pose.  This preserves the source's global
        # limb direction while respecting Bob's bone rolls and hierarchy.
        for target_name, source_name in MAPPING.items():
            source_bone = source.pose.bones[source_name]
            target_bone = target.pose.bones[target_name]
            source_data = source.data.bones[source_name]
            target_data = target.data.bones[target_name]
            desired_rotation = (target_data.matrix_local.to_quaternion()
                                @ source_data.matrix_local.to_quaternion().inverted()
                                @ source_bone.matrix.to_quaternion())
            if target_bone.parent:
                basis_rotation = (target_data.matrix_local.to_quaternion().inverted()
                    @ target_bone.parent.bone.matrix_local.to_quaternion()
                    @ target_bone.parent.matrix.to_quaternion().inverted()
                    @ desired_rotation)
            else:
                basis_rotation = (target_data.matrix_local.to_quaternion().inverted()
                                  @ desired_rotation)
            target_bone.rotation_mode = "QUATERNION"
            # Bone lengths and translations are deliberately left on Bob's
            # rest skeleton.  Copying FBX global translations was stretching
            # calves because the two skeletons have different proportions.
            target_bone.location = (0.0, 0.0, 0.0)
            target_bone.scale = (1.0, 1.0, 1.0)
            target_bone.rotation_quaternion = basis_rotation
            # PoseBone.matrix is dependency-graph evaluated; without this,
            # a child can solve against its parent's value from the previous
            # sample frame.
            bpy.context.view_layer.update()
            target_bone.keyframe_insert(data_path="rotation_quaternion", frame=frame)
    bpy.context.scene.frame_start = 1
    bpy.context.scene.frame_end = OUTPUT_END
    bpy.context.scene.frame_set(1)
    source.hide_render = True
    source.hide_viewport = True
    blend_path.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(blend_path))
    bpy.ops.export_scene.directx_x(filepath=str(output_x), export_animation=True,
                                   export_armature=True, export_weights=True,
                                   pz_compat=True, anim_frame_start=1,
                                   anim_frame_end=OUTPUT_END,
                                   anim_key_format="TRS", export_format="TEXT_X")


if __name__ == "__main__":
    main()
