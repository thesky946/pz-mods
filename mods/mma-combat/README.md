# MMA Combat

MVP: unequip weapons and attack. The mod overrides `Base.BareHands`, so the vanilla server combat path resolves damage in both SP and MP. The unarmed clip is authored in Blender on the vanilla Bob armature and exported as `common/media/anims_X/Bob/Bob_Shove.X`; its Blender source is `assets/Bob_Shove.blend`.

```powershell
.\tools\check.ps1 -Mod mma-combat
.\tools\watch.cmd mma-combat
```

Before first publication, set workshopid in mod-manifest.json.

## Motion-capture source

`assets/source-mocap/135_07_mawashigeri.*` is trial 7 (Mawashigeri) from subject 135 of the [Carnegie Mellon University Graphics Lab Motion Capture Database](https://mocap.cs.cmu.edu/). The database permits use but does not permit direct resale of its data. It was created with funding from NSF EIA-0196217.
