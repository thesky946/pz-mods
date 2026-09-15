"""Render selected source FBX frames for animation review."""
import sys
from pathlib import Path
import bpy
from mathutils import Vector

source, output, frame = Path(sys.argv[sys.argv.index("--") + 1]), Path(sys.argv[sys.argv.index("--") + 2]), int(sys.argv[sys.argv.index("--") + 3])
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=str(source))
scene = bpy.context.scene
scene.frame_set(frame)
meshes = [o for o in scene.objects if o.type == "MESH"]
print("MESHES", [(o.name, len(o.data.vertices)) for o in meshes])
points = [o.matrix_world @ Vector(c) for o in meshes for c in o.bound_box]
if not points:
    rig = next(o for o in scene.objects if o.type == "ARMATURE")
    curve = bpy.data.curves.new("motion_skeleton", "CURVE")
    curve.dimensions = "3D"
    curve.bevel_depth = .018
    curve.bevel_resolution = 2
    skeleton = bpy.data.objects.new("motion_skeleton", curve)
    bpy.context.collection.objects.link(skeleton)
    for bone in rig.pose.bones:
        head = rig.matrix_world @ bone.matrix.translation
        tail = rig.matrix_world @ (bone.matrix @ Vector((0, bone.bone.length, 0)))
        spline = curve.splines.new("POLY")
        spline.points.add(1)
        spline.points[0].co = (*head, 1)
        spline.points[1].co = (*tail, 1)
        points.extend((head, tail))
minimum = Vector(tuple(min(p[i] for p in points) for i in range(3)))
maximum = Vector(tuple(max(p[i] for p in points) for i in range(3)))
center = (minimum + maximum) * .5
radius = max(maximum-minimum)*.75
bpy.ops.object.camera_add(location=center+Vector((radius*1.45, -radius*2.1, radius*.85)))
cam=bpy.context.object
cam.rotation_euler=(center-cam.location).to_track_quat('-Z','Y').to_euler()
cam.data.lens=52
scene.camera=cam
scene.render.engine='BLENDER_WORKBENCH'
scene.display.shading.light='STUDIO'; scene.display.shading.studio_light='paint.sl'; scene.display.shading.color_type='MATERIAL'
scene.render.resolution_x=512; scene.render.resolution_y=512; scene.render.resolution_percentage=100
scene.render.image_settings.file_format='PNG'; scene.render.filepath=str(output)
bpy.ops.render.render(write_still=True)
