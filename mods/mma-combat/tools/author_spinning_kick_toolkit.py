"""Author a spinning heel kick on Paddlefruit's PZ Toolkit vanilla IK rig.

The action remains on the exact PZ deform skeleton; the Toolkit then exports
that skeleton to B42 GLB.  This deliberately avoids its currently stale
"Add Animation to Rig" importer.
"""
import sys
import os
from pathlib import Path

import bpy
from mathutils import Euler

TOOLKIT_ROOT = Path(os.environ["TEMP"]) / "PZ_BlenderToolkit-v5.0.0PR2-inspect"
if str(TOOLKIT_ROOT) not in sys.path:
    sys.path.append(str(TOOLKIT_ROOT))
import PZ_BlenderToolkit


def paths():
    values = sys.argv[sys.argv.index("--") + 1:]
    return Path(values[0]), Path(values[1])


def key(pb, frame):
    pb.keyframe_insert(data_path="location", frame=frame)
    pb.keyframe_insert(data_path="rotation_quaternion", frame=frame)


def main():
    source, output = paths()
    PZ_BlenderToolkit.register()
    bpy.ops.wm.open_mainfile(filepath=str(source))
    rig = next(o for o in bpy.context.scene.objects if o.type == "ARMATURE")
    bpy.context.view_layer.objects.active = rig
    rig.select_set(True)

    # These properties drive the rig's IK/FK constraint influences.  Assigning
    # influences directly does not work because the Toolkit correctly restores
    # them through drivers on every evaluation.
    rig.pz_animation_properties.leg_ik_l = 1.0
    rig.pz_animation_properties.leg_ik_r = 1.0

    action = bpy.data.actions.new("Bob_SpinningKick")
    rig.animation_data_create()
    rig.animation_data.action = action
    scene = bpy.context.scene
    scene.frame_start, scene.frame_end = 1, 40

    root = rig.pose.bones["CTRL-Root"]
    pelvis = rig.pose.bones["CTRL-Pelvis"]
    kick = rig.pose.bones["CTRL-LegIK.R"]
    plant = rig.pose.bones["CTRL-LegIK.L"]
    knee = rig.pose.bones["CTRL-KneeTarget.R"]
    left_knee = rig.pose.bones["CTRL-KneeTarget.L"]

    # Local offsets are intentionally keyed, rather than hard-coded world
    # positions: child-of constraints keep the plant foot attached through
    # the pivot and the kick tracks naturally with the turn.
    poses = {
        # frame: root yaw, pelvis lean, right-foot offset, left-foot offset, knee offset
        1:  (0,   (0, 0, 0),        (0, 0, 0),       (0, 0, 0),      (0, 0, 0)),
        7:  (22,  (0, -4, 0),       (0, 0, 9),        (0, 0, 0),      (0, -2, 4)),
        13: (105, (0, -7, 2),       (0, -14, 23),     (0, 0, -2),     (0, -8, 9)),
        # Heel reaches head height after a compact chamber; contact is f19.
        19: (188, (0, -6, 2),       (0, -38, 35),     (0, 0, -3),     (0, -16, 14)),
        25: (262, (0, -2, 1),       (0, -17, 18),     (0, 0, -1),     (0, -6, 7)),
        33: (334, (0, 0, 0),        (0, -3, 3),       (0, 0, 0),      (0, 0, 2)),
        40: (360, (0, 0, 0),        (0, 0, 0),       (0, 0, 0),     (0, 0, 0)),
    }
    for frame, (yaw, p, k, l, kn) in poses.items():
        scene.frame_set(frame)
        root.rotation_mode = "QUATERNION"
        # The PZ root's local Y axis is the character's vertical turn axis.
        root.rotation_quaternion = Euler((0, yaw * 0.01745329252, 0), "XYZ").to_quaternion()
        pelvis.location = p
        kick.location = k
        plant.location = l
        knee.location = kn
        left_knee.location = (0, 0, 0)
        for control in (root, pelvis, kick, plant, knee, left_knee):
            control.rotation_mode = "QUATERNION"
            key(control, frame)

    for layer in action.layers:
        for strip in layer.strips:
            for bag in strip.channelbags:
                for curve in bag.fcurves:
                    for point in curve.keyframe_points:
                        point.interpolation = "BEZIER"
                    curve.update()

    scene.frame_set(1)
    output.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(output))


if __name__ == "__main__":
    main()
