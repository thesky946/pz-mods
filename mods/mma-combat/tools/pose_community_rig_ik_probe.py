"""Headless IK contact-pose probe for the PZ Community Rig (temporary QA tool)."""
import bpy
import math
import os
from mathutils import Matrix, Vector

OUT = os.path.join(os.environ["TEMP"], "mma-community-rig-preview")
os.makedirs(OUT, exist_ok=True)

rig = bpy.data.objects["OBJ-HumanRig (0)"]
scene = bpy.context.scene


def set_ik(side, enabled=True):
    """Switch the published deform bones between Community Rig FK and IK."""
    suffix = "." + side
    for bone_name in ("Bip01_" + side + "_Thigh", "Bip01_" + side + "_Calf"):
        bone = rig.pose.bones[bone_name]
        bone.constraints["Copy FK Location"].influence = 0.0 if enabled else 1.0
        bone.constraints["Copy FK Rotation"].influence = 0.0 if enabled else 1.0
        bone.constraints["Copy IK Location"].influence = 1.0 if enabled else 0.0
        bone.constraints["Copy IK Rotation"].influence = 1.0 if enabled else 0.0
    foot = rig.pose.bones["Bip01_" + side + "_Foot"]
    foot.constraints["Copy FK Rotation"].influence = 0.0 if enabled else 1.0
    foot.constraints["Copy IK Rotation"].influence = 1.0 if enabled else 0.0


def world_target(name, location, yaw_degrees=0):
    """Assign an IK control by world transform, avoiding local Euler guesses."""
    control = rig.pose.bones[name]
    rest_axes = control.bone.matrix_local.to_3x3().to_4x4()
    control.matrix = (
        Matrix.Translation(Vector(location))
        @ Matrix.Rotation(math.radians(yaw_degrees), 4, "Z")
        @ rest_axes
    )


# The kicking right leg is solved from a target at head height.  The other leg
# stays on the floor in IK, making balance failures immediately visible.
set_ik("R", True)
set_ik("L", True)
world_target("CTRL-LegIK.L", (10.648, 5.101, 7.122), 0)
world_target("CTRL-KneeTarget.L", (7.0, -25.0, 25.0), 0)
world_target("CTRL-LegIK.R", (-22.0, -5.0, 51.0), 88)
world_target("CTRL-KneeTarget.R", (-13.0, -25.0, 39.0), 0)

# Turn the torso through its actual rest matrix; root local-Y is world-up on
# this rig, so no hard-coded XYZ control Euler values are used.
root = rig.pose.bones["CTRL-Root"]
root.matrix = (
    Matrix.Translation(root.bone.head_local)
    @ Matrix.Rotation(math.radians(125), 4, "Z")
    @ root.bone.matrix_local.to_3x3().to_4x4()
)

# Guard: world-space control transforms retain the arms upright while the body
# turns. This keeps a combat silhouette rather than a T-pose.
world_target("CTRL-ArmIK.L", (20.0, -2.0, 69.0), 0)
world_target("CTRL-ElbowTarget.L", (17.0, -16.0, 65.0), 0)
world_target("CTRL-ArmIK.R", (-17.0, -6.0, 66.0), 0)
world_target("CTRL-ElbowTarget.R", (-16.0, -17.0, 62.0), 0)

bpy.context.view_layer.update()

# Structural QA: target must be met and the support foot must stay near floor.
right_foot = rig.pose.bones["Bip01_R_Foot"].head
left_foot = rig.pose.bones["Bip01_L_Foot"].head
assert (right_foot - Vector((-22.0, -5.0, 51.0))).length < 0.02, right_foot
assert 0.0 < left_foot.z < 12.0, left_foot
assert rig.pose.bones["Bip01_R_Calf"].head.z > 20.0

# Camera and preview render.
cam_data = bpy.data.cameras.new("MMA_IK_Probe_Camera")
cam = bpy.data.objects.new("MMA_IK_Probe_Camera", cam_data)
scene.collection.objects.link(cam)
cam.location = (72.0, -105.0, 58.0)
cam.rotation_euler = (Vector((0.0, 0.0, 38.0)) - cam.location).to_track_quat("-Z", "Y").to_euler()
cam.data.lens = 58
scene.camera = cam
scene.render.engine = "BLENDER_WORKBENCH"
scene.display.shading.light = "STUDIO"
scene.display.shading.studio_light = "rim.sl"
scene.display.shading.color_type = "MATERIAL"
scene.display.shading.show_shadows = True
scene.display.shading.show_cavity = True
scene.render.resolution_x = 720
scene.render.resolution_y = 720
scene.render.resolution_percentage = 100
scene.render.filepath = os.path.join(OUT, "ik-contact-probe.png")
bpy.ops.render.render(write_still=True)
print("CONTACT", tuple(round(v, 3) for v in right_foot))
print("SUPPORT", tuple(round(v, 3) for v in left_foot))
print("WROTE", scene.render.filepath)
