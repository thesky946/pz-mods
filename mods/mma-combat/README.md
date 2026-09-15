# MMA Combat

MVP: unequip weapons and attack. The mod overrides `Base.BareHands`, so the vanilla server combat path resolves damage in both SP and MP. The unarmed clip is authored in Blender on the vanilla Bob armature and exported as `common/media/anims_X/Bob/Bob_Shove.X`; its Blender source is `assets/Bob_Shove.blend`.

```powershell
.\tools\check.ps1 -Mod mma-combat
.\tools\dev.cmd mma-combat
```

Before first publication, set workshopid in mod-manifest.json.
