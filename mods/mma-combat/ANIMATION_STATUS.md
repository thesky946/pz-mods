# Spinning heel kick — experiment archived

Date: 2026-09-15. Status: **not production-ready; do not sync or publish.**

## What is proven

- Project Zomboid B42 accepts custom player animation assets. The B42 mod
  Sprockets (Workshop `3800471544`) uses the practical pipeline:
  motion source -> Blender -> Paddlefruit Project Zomboid Community Rig ->
  retarget/touch-up -> GLB -> AnimSet.
- Paddlefruit's Community Rig / Blender Toolkit V5 PR2 opens correctly in
  Blender 5.2.1 and its GLB exporter is usable.
- The vanilla Bob skeleton can be authored and exported as a PZ `.X` clip;
  `common/media/anims_X/Bob/Bob_Shove.X` is an experimental clip only.
- The gameplay prototype is structurally wired through `Base.BareHands` and
  uses the normal vanilla combat path, so it is intended for SP and MP.
  It has **not** been validated in either game mode.

## What failed

1. Procedural native Bob keyframes produced a recognizable raised-leg pose,
   but not a convincing spinning heel/hook kick. Recovery and balance are bad.
2. CMU `mawashigeri` is a roundhouse rather than the requested spinning heel
   kick. Automatic retargeting broke pose orientation because Bob and the
   source use different rest poses, bone axes and hierarchy.
3. AI/mocap `spinning heel kick` was useful as reference, not as a finished
   asset. Automatic global retargeting still produced invalid support-foot,
   pelvis and recovery motion. Its raw source must not be redistributed.
4. Community Rig V4 and Toolkit V5 PR2 both retain stale mappings in
   `Add Animation to Rig` (`CTRL-Hand.*` / `CTRL-Foot.*` versus current FK
   controls). Their automatic import must not be trusted for this project.
5. Toolkit V5 IK itself works through driver-backed properties, not naïve bone
   transforms. The first scripted IK attempt is visibly wrong and is retained
   only as a diagnostic in `assets/`; it is not an animation candidate.
6. AnimForge was not installed: its engine patch was compiled for an older PZ
   Steam build than the installed B42.20. Forcing it would replace engine
   classes and risk corrupting the game.

## Why this is paused

There is no technical impossibility. The unsolved part is quality: a combat
kick requires a believable turn, chamber, heel contact, planted support foot,
weight transfer and guarded recovery. Neither AI generation nor current
automatic retargeting delivers those reliably on Bob.

Continuing with scripted guesses would create more misleading clips, not a
release asset.

## Conditions for resuming

1. Obtain a licensed spinning heel/hook-kick mocap clip, or record one.
2. Use the Community Rig as the final PZ control rig, not an automatic importer.
3. Manually polish the five critical poses in Blender: guard, turn, chamber,
   heel contact, recovery. Check support-foot lock and centre of mass.
4. Export a `Bob_SpinningKick.glb` using the Toolkit exporter.
5. Register it through an AnimSet/vanilla action path, then test in a fresh
   single-player session and hosted/dedicated multiplayer.
6. Only after visual and in-game proof, replace the experimental `Bob_Shove.X`
   and publish.

## Archived evidence

- `assets/native-*.png`: direct-Bob test renders.
- `assets/toolkit-*.png`: Community Rig V5 diagnostic renders; wrong, retained
  to avoid retrying the same controller-axis/driver mistake.
- `tools/author_spinning_kick_in_blender.py`: direct Bob experiment.
- `tools/retarget_cmu_spinning_kick.py`: failed automatic retarget experiment.
- `tools/author_spinning_kick_toolkit.py`: V5 IK diagnostic; not a final authoring tool.

## Recommendation

Pause the animation feature. If MMA Combat is resumed before a real animation
source is available, build non-animation mechanics separately: stamina,
unarmed damage, knockdown, range and multiplayer authority.
