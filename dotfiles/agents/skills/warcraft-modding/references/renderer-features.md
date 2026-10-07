# Renderer features since Reforged

The complete per-patch index (natives, editor fields, script access, graphics
modes, cost, sources) is smashcraft:docs/design/warcraft-features.md; check
names against the pinned common.j (wisp:src/natives/warcraft.d.ts).

- **Only 3.0.0 (Forsaken Kingdom, Sept 2026) added graphics natives.**
  1.33–1.36 added none, 2.0.x changed shaders, tone map and assets without
  natives. Reach for 3.0 first:
  - fog: `SetTerrainFogExV` and `BlzSetTerrainFog{Style,ZStart,ZEnd,Density,
    HeightStart,HeightEnd,LinearStart,LinearEnd,MaxLinearDensity,DrawOverSky,
    Color}`, styles `FOG_STYLE_HEIGHT`, `_NEW_EXP`, `_NEW_EXP_2`;
  - HD water: `SetHDWaterParams[Ex]`, `BlzSetHDWater*` (HD and the player's
    Water option only);
  - `BlzSetMinShadowCastingPointLightCount`, depth-of-field camera fields,
    doodad/destructable colour and per-doodad animation natives.
- **1.32 still matters:** `BlzShowTerrain`/`BlzShowSkyBox` (hide terrain or
  sky), `CameraSetFocalDistance` (HD), skins, `SetPortraitLight`.
- **Editor-only, no native:** the 3.0 lighting editor and omni lights,
  map post-processing. A script gets lights only from models that contain
  them (unlimited in HD since 3.0, capped in Classic).
- **Impossible:** shaders, LUTs, bloom or exposure control, reading or
  choosing the graphics mode, driving PopcornFX particles.
- Day/night lighting models still drive key and fill light (`SetDayNightModels`);
  2.0 broke custom ones, so measure them on the current client.
