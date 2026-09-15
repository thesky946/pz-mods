"""Inspect the licensed Motifect spinning heel kick source in Blender."""
import csv
import sys
from pathlib import Path
import bpy


def paths():
    return tuple(Path(v) for v in sys.argv[sys.argv.index("--") + 1:])


def main():
    source_path, report_path = paths()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.fbx(filepath=str(source_path))
    rig = next(o for o in bpy.context.scene.objects if o.type == "ARMATURE")
    scene = bpy.context.scene
    print("RIG", rig.name, "frames", scene.frame_start, scene.frame_end)
    print("RIG_ROT_MODE", rig.rotation_mode, "ACTION", rig.animation_data.action.name if rig.animation_data and rig.animation_data.action else None)
    if rig.animation_data and rig.animation_data.action:
        action = rig.animation_data.action
        curves = []
        for layer in action.layers:
            for strip in layer.strips:
                for bag in strip.channelbags:
                    curves.extend(bag.fcurves)
        print("ROOT_FCURVES", ",".join(curve.data_path for curve in curves))
    print("BONES", ",".join(b.name for b in rig.data.bones))
    rows = []
    for frame in range(scene.frame_start, scene.frame_end + 1):
        scene.frame_set(frame)
        left_hip = rig.pose.bones["LeftLeg"].head
        right_hip = rig.pose.bones["RightLeg"].head
        for side in ("Left", "Right"):
            foot = rig.pose.bones[side + "Foot"].tail
            toe = rig.pose.bones.get(side + "ToeBase")
            pos = rig.matrix_world @ (toe.tail if toe else foot)
            hip = rig.matrix_world @ (left_hip if side == "Left" else right_hip)
            rows.append({"frame": frame, "side": side, "x": pos.x, "y": pos.y, "z": pos.z,
                         "reach": (pos - hip).length, "height": pos.z,
                         "root_rot_z": rig.rotation_euler.z})
    report_path.parent.mkdir(parents=True, exist_ok=True)
    with report_path.open("w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=rows[0].keys())
        writer.writeheader(); writer.writerows(rows)
    for side in ("Left", "Right"):
        samples = [r for r in rows if r["side"] == side]
        print(side, "highest", max(samples, key=lambda r:r["height"]), "furthest", max(samples, key=lambda r:r["reach"]))


if __name__ == "__main__":
    main()
