---
name: game-design-prototyping
description: >-
  Design and build playable game prototypes and worlds using Tom's local Quaternius models, scenery, and animation library; make navigation and combat legible without placeholder actors.
grounded: 2026-10-09
written: 2026-10-09
---

# Game design and prototyping

- Use the project's design and engine to build the smallest playable route or encounter that tests its intended player decision.
- Inspect ~/code/game-assets/quaternius/ before creating actor or scenery visuals or seeking downloads.
- Inspect `All in One - Quaternius[Patreon].zip` for animated characters, animals, monsters, medieval villages, props, nature and Universal Animation Libraries 1 and 2.
- Inspect `Universal Animation Library[Standard].zip` for Universal Animation Library 1.
- Verify actual clip names and skeleton compatibility before selecting animations.
- Use suitable library models and animations for visible actors and available scenery.
- Reserve primitives for invisible collision, navigation debugging, terrain, deliberate attack/selection graphics or a requested geometry blockout.
- Identify a concrete asset gap and choose deliberate art when the library lacks a suitable model.
- Extract only the chosen coherent subset of models, buffers, textures, animations and license notices into the project's assets.
- Keep shared archives intact and outside game repositories and web releases.
- Prefer glTF/GLB where supported.
- Preserve pack names and archive member paths in the project's attribution record.
- Retain and check selected packs' bundled terms, including Patreon-labelled content, against the all-in-one root License.txt's CC0 1.0 Universal declaration.
- Compose recognizable hubs, forest edges, clear paths, landmarks, useful clearings and a way home with compatible scale, materials and silhouettes.
- Keep scenery out of combat sightlines and leave clear ground for attack warnings.
- Align visible obstacles and paths with movement and collision.
- Align the normal camera, map, objectives and world markers with the same geography.
- Distinguish players, enemies, targets and damage areas at the actual viewport size.
- Place labels away from bodies and action without oversized foreground text or overlapping map text.
- Preserve readability when adding decorative density, fog or darkness.
- Choose creatures with usable authored idle, locomotion, preparation, attack, recovery, hit and defeat clips as the encounter requires.
- Use compatible native clips before retargeting after checking skeleton bindings.
- Let gameplay own displacement unless the movement model explicitly uses root motion.
- Show impending attacks, their committed target or area and the available response through visible body animation.
- Align animation, warnings, damage, defense and recovery with gameplay timing.
- Keep nearby enemies individually identifiable without covering the world in panels.
- Run the existing browser or game journey through navigation, enemy identification, warning, response and outcome.
- Inspect the normal camera and animation playback before declaring readiness.
- Report missing art or unobserved behavior plainly.
