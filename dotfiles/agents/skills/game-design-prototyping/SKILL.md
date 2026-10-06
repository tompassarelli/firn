---
name: game-design-prototyping
description: >-
  Design and build playable game prototypes and worlds using Tom's local Quaternius models, scenery, and animation library; make navigation and combat legible without placeholder actors.
---

# Game design and prototyping

Use the project's current game design and chosen engine. Build the smallest
playable route or encounter that tests its intended player decision. This
skill does not select a new engine or replace the project's design.

## Use the asset library

Tom's existing library is **~/code/game-assets/quaternius/**:

- ~/code/game-assets/quaternius/All in One - Quaternius[Patreon].zip
- ~/code/game-assets/quaternius/Universal Animation Library[Standard].zip

Inspect these local archives before creating character, enemy, NPC, building,
prop, or vegetation visuals or looking for more downloads. The all-in-one
archive includes animated characters, animals and monsters, medieval village
and prop kits, nature packs, and Universal Animation Libraries 1 and 2.
The separate archive also contains Universal Animation Library 1. Inspect
actual clip names and skeletons; archive names do not prove compatibility.

Use suitable authored models and animations from this library instead of
capsules, pills, spheres, cones, or boxes standing in for visible actors or
available scenery. A playable prototype should already communicate what its
people, creatures, and places are. Invisible collision shapes, navigation
debug views, terrain surfaces, and deliberate attack-area or selection
graphics remain appropriate uses of primitives. A specifically requested
geometry blockout is a separate deliverable; do not present it as the finished
visual prototype. If no asset fits a required role, identify the concrete gap
and make a deliberate art choice instead of silently shipping a placeholder.

List archive contents, select a coherent subset, and extract only the needed
models, buffers, textures, animations, and license notices into the project's
asset directory. Keep the shared archives intact and out of game repositories
and web releases. Prefer glTF/GLB where supported. Preserve source pack names
and archive member paths in the project's asset attribution record. The
all-in-one archive's root License.txt declares CC0 1.0 Universal; retain and
check the selected packs' bundled terms, including Patreon-labelled content.

## Make the world readable

Compose a place rather than scattering an asset inventory. Choose compatible
scale, materials, and silhouettes; group buildings into a recognizable hub
and vegetation into forest edges. Establish clear paths, distinctive
landmarks, useful clearings, and a recognizable way home. Keep scenery out of
combat sightlines and preserve enough clear ground to read attack warnings.
Visible obstacles and paths must agree with actual movement and collision.

The normal play camera, map, objective, and world markers must describe the
same geography. Keep the player, enemies, target indicators, and damage areas
distinguishable at the actual viewport size. Place labels away from bodies
and the action; avoid oversized foreground labels and overlapping map text.
Do not spend the readability budget on decorative density, fog, or darkness.

## Make behavior visible

Choose creatures around usable authored animations. Hook up idle, locomotion,
preparation, attack, recovery, hit reaction, and defeat as the encounter needs;
do not call a static model with a bob or defeat tilt an animated enemy.
Use native compatible clips first. Verify skeleton bindings before retargeting
an animation library, and let gameplay own displacement unless root motion is
explicitly part of the game's movement model.

For deliberate intent-based combat, show what is coming, its committed target
or area, and the available response. The body animation, warning, damage,
defense, and recovery window must follow the same gameplay timing. A countdown
alone does not communicate an attack. Keep several nearby enemies individually
identifiable without burying the world beneath panels.

Use the existing browser or game journey to observe the actual scene: navigate
the route, identify an enemy, read a warning, respond, and see the outcome.
Inspect the normal camera view and animation playback before calling the
prototype ready. Report missing art or unobserved behavior plainly.
