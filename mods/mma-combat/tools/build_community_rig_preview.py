"""Create a native Community Rig spinning heel-kick preview outside the mod output."""
import bpy
import math
import os
from mathutils import Euler
from mathutils import Vector

OUT = os.path.join(os.environ["TEMP"], "mma-community-rig-preview")
BLEND = os.path.join(OUT, "Bob_SpinningKick_CommunityRig.blend")
GLB = os.path.join(OUT, "Bob_SpinningKick.glb")

os.makedirs(OUT, exist_ok=True)
rig = bpy.data.objects["OBJ-HumanRig (0)"]
bpy.context.view_layer.objects.active = rig
rig.select_set(True)
scene = bpy.context.scene
scene.render.fps = 30
scene.frame_start = 1
scene.frame_end = 100

if rig.animation_data:
    rig.animation_data_clear()
action = bpy.data.actions.new("Bob_SpinningKick")
rig.animation_data_create()
rig.animation_data.action = action

def rad(x): return math.radians(x)

controls = [
    "CTRL-Root", "CTRL-Pelvis", "CTRL-Spine1", "CTRL-Spine2",
    "CTRL-ThighFK.L", "CTRL-CalfFK.L", "CTRL-FootFK.L",
    "CTRL-ThighFK.R", "CTRL-CalfFK.R", "CTRL-FootFK.R",
    "CTRL-UpperArmFK.L", "CTRL-ForearmFK.L", "CTRL-HandFK.L",
    "CTRL-UpperArmFK.R", "CTRL-ForearmFK.R", "CTRL-HandFK.R",
]

for name in controls:
    b = rig.pose.bones[name]
    b.rotation_mode = "XYZ"

# Key poses: guarded stance -> load -> turn -> head-height heel contact -> recovery.
poses = {
    1:  {"CTRL-Root":(0,0,0), "CTRL-Pelvis":(0,0,0), "CTRL-Spine1":(0,0,0), "CTRL-Spine2":(0,0,0),
         "CTRL-ThighFK.L":(0,0,0), "CTRL-CalfFK.L":(0,0,0), "CTRL-FootFK.L":(0,0,0),
         "CTRL-ThighFK.R":(0,0,0), "CTRL-CalfFK.R":(0,0,0), "CTRL-FootFK.R":(0,0,0),
         "CTRL-UpperArmFK.L":(-35,15,25), "CTRL-ForearmFK.L":(-65,0,0),
         "CTRL-UpperArmFK.R":(-35,-15,-25), "CTRL-ForearmFK.R":(-65,0,0)},
    35: {"CTRL-Root":(0,0,20), "CTRL-Pelvis":(0,8,22), "CTRL-Spine1":(0,-8,-12), "CTRL-Spine2":(0,-8,-8),
         "CTRL-ThighFK.L":(18,8,-12), "CTRL-CalfFK.L":(-15,0,0), "CTRL-FootFK.L":(8,0,0),
         "CTRL-ThighFK.R":(-35,5,10), "CTRL-CalfFK.R":(55,0,0), "CTRL-FootFK.R":(-18,0,0),
         "CTRL-UpperArmFK.L":(-50,25,40), "CTRL-ForearmFK.L":(-65,0,0),
         "CTRL-UpperArmFK.R":(-50,-25,-40), "CTRL-ForearmFK.R":(-65,0,0)},
    50: {"CTRL-Root":(0,0,105), "CTRL-Pelvis":(0,5,55), "CTRL-Spine1":(0,-5,-24), "CTRL-Spine2":(0,-3,-12),
         "CTRL-ThighFK.L":(20,18,-8), "CTRL-CalfFK.L":(-10,0,0), "CTRL-FootFK.L":(5,0,0),
         "CTRL-ThighFK.R":(-72,8,20), "CTRL-CalfFK.R":(88,0,0), "CTRL-FootFK.R":(-22,0,0),
         "CTRL-UpperArmFK.L":(-45,15,55), "CTRL-ForearmFK.L":(-70,0,0),
         "CTRL-UpperArmFK.R":(-45,-15,-55), "CTRL-ForearmFK.R":(-70,0,0)},
    60: {"CTRL-Root":(0,0,180), "CTRL-Pelvis":(0,0,85), "CTRL-Spine1":(0,0,-42), "CTRL-Spine2":(0,0,-15),
         "CTRL-ThighFK.L":(12,0,5), "CTRL-CalfFK.L":(0,0,0), "CTRL-FootFK.L":(0,0,0),
         "CTRL-ThighFK.R":(-112,0,8), "CTRL-CalfFK.R":(6,0,0), "CTRL-FootFK.R":(-10,0,0),
         "CTRL-UpperArmFK.L":(-30,10,65), "CTRL-ForearmFK.L":(-65,0,0),
         "CTRL-UpperArmFK.R":(-30,-10,-65), "CTRL-ForearmFK.R":(-65,0,0)},
    75: {"CTRL-Root":(0,0,235), "CTRL-Pelvis":(0,-5,38), "CTRL-Spine1":(0,4,-22), "CTRL-Spine2":(0,3,-8),
         "CTRL-ThighFK.L":(10,0,0), "CTRL-CalfFK.L":(0,0,0), "CTRL-FootFK.L":(0,0,0),
         "CTRL-ThighFK.R":(-55,0,0), "CTRL-CalfFK.R":(62,0,0), "CTRL-FootFK.R":(-12,0,0),
         "CTRL-UpperArmFK.L":(-38,18,35), "CTRL-ForearmFK.L":(-62,0,0),
         "CTRL-UpperArmFK.R":(-38,-18,-35), "CTRL-ForearmFK.R":(-62,0,0)},
    100:{"CTRL-Root":(0,0,360), "CTRL-Pelvis":(0,0,0), "CTRL-Spine1":(0,0,0), "CTRL-Spine2":(0,0,0),
         "CTRL-ThighFK.L":(0,0,0), "CTRL-CalfFK.L":(0,0,0), "CTRL-FootFK.L":(0,0,0),
         "CTRL-ThighFK.R":(0,0,0), "CTRL-CalfFK.R":(0,0,0), "CTRL-FootFK.R":(0,0,0),
         "CTRL-UpperArmFK.L":(-35,15,25), "CTRL-ForearmFK.L":(-65,0,0),
         "CTRL-UpperArmFK.R":(-35,-15,-25), "CTRL-ForearmFK.R":(-65,0,0)},
}

for frame, values in poses.items():
    scene.frame_set(frame)
    for name in controls:
        b = rig.pose.bones[name]
        v = values.get(name, (0,0,0))
        b.rotation_euler = Euler(tuple(rad(x) for x in v), "XYZ")
        b.keyframe_insert("rotation_euler", frame=frame, group=name)

scene.frame_set(60)
# Dedicated inspection camera.  The Community Rig's scene cameras are for its
# asset showcase and do not frame arbitrary combat poses.
cam = bpy.data.objects.get("MMA_PreviewCamera")
if cam is None:
    cam_data = bpy.data.cameras.new("MMA_PreviewCamera")
    cam = bpy.data.objects.new("MMA_PreviewCamera", cam_data)
    bpy.context.collection.objects.link(cam)
cam.location = (2.4, -3.2, 1.25)
target = Vector((0.0, 0.0, 0.0))
cam.rotation_euler = (target - cam.location).to_track_quat('-Z', 'Y').to_euler()
cam.data.lens = 52
scene.camera = cam
scene.render.engine = 'BLENDER_WORKBENCH'
scene.display.shading.light = 'STUDIO'
scene.display.shading.studio_light = 'rim.sl'
scene.display.shading.color_type = 'MATERIAL'
scene.display.shading.show_shadows = True
scene.display.shading.show_cavity = True
scene.render.resolution_x = 720
scene.render.resolution_y = 720
scene.render.resolution_percentage = 100
bpy.ops.wm.save_as_mainfile(filepath=BLEND)

# GLB preview using the rig's evaluated deform skeleton. It is an inspection asset, not mod output.
print('WROTE', BLEND)
