---
name: smashcraft-stage-design
description: >-
  Design, dress and judge a Smashcraft stage's look: backdrop, scenery bands,
  set pieces, the deck's underside, water, sky, light and fighter contrast, in
  Classic and Definitive. Use for any stage art, stage composition or stage
  look issue, a new stage, or a stage review.
---

# Smashcraft stage design

The rules a stage must meet, and their numbers, are in
smashcraft:docs/design/stage-art.md and smashcraft:docs/design/visual-quality.md.
This skill is how to meet them and how to judge the result. Lighting
packages, contrast rows and asset storage follow the existing stage pattern
(Blackrock fix 36f3f1d45: copy the stage-asset family, then `bun wisp inputs add`).

## Look at the references first

Tom's reference set is ~/.local/share/smashcraft-stage-references/. Read its
README.md and open the images. They are Nintendo screenshots for judgement
only: never commit them, import them or trace them.

Before you change a stage, pick the layout type it uses and name one
reference that has it:
- **Horizon band:** Smashville, Battlefield, Delfino Plaza, Wuhu Island.
- **Close set pieces:** Fountain of Dreams, Pokémon Stadium.
- **Enclosed arena:** Boxing Ring.
- **The stage is a big object:** Pirate Ship, Corneria.
- **Floating island over a vivid sky:** Final Destination.

Also open `00-anti-smashcraft-tomb-0.0.100.png`. It is what we shipped and
Tom rejected, and your result must not look like it.

## What makes a stage look good
1. **The frame is full.** No flat single-colour backdrop shows through the
   middle of the frame. The fill comes from a scenery band, close set pieces,
   an enclosing structure, the stage's own mass, or a vivid painted sky.
   Three props in the distance is the failure.
2. **The deck sits in something.** Scenery, water or structure sits under and
   beside it, or a modelled underside mass. The underside is never one
   texture tiled flat.
3. **Landmarks are big.** The stage's landmark (temple, portal, cathedral)
   is a large, recognisable part of the frame at match zoom, close behind the
   deck, not a corner prop. Small accents add to the landmark; they don't
   replace it.
4. **Water reads as water.** A full-width surface at the water's real
   height, lighter than its surroundings, with ripples. The stage's supports
   go into it. Fighters show a splash on entry and swim visibly.
5. **The fighters stay brightest and clearest.** The fighting area is lit
   most. Saturation and contrast fall off with depth. The contrast rows must
   still pass.
6. **One place.** The platforms, deck and scenery come from the same world
   and the same light. Use stock Warcraft III assets first.
7. **Both looks are complete scenes,** Classic and Definitive, at both camera
   extremes. Nothing is clipped at the frame edges, and the side platforms
   are fully inside the frame.

## How to judge
- **Judge at match zoom** in both the near and far views, at 16:9, next to
  the chosen reference. A close-up of a prop proves nothing.
- **Measure the empty backdrop:** the share of pixels below the horizon that
  show only the backdrop or sky colour. Use the limit in visual-quality.md
  (#360).
- **Wisp frames first, then one native capture** on the LAN pool. Confirm the
  pool's mode actually took effect: Classic and Definitive frames must
  differ (wisp#79, 9 Oct).
- **Squint test:** look at the frame in grayscale, scaled down to about 320
  pixels wide. The fighters and ledges should read first, and the frame
  should have no large empty field.
- **Report with images.** Post the before and after frames next to the
  reference on the issue. Say which reference you matched and which rule
  each change serves.

## Don'ts
- Don't change collision, blast zones, platform positions or frame cost for
  art; the art follows the stage's geometry.
- Don't trust a contrast pass as proof that a stage looks good. Tomb passed
  every contrast row and was still a void.
- Don't ship a fix that Tom hasn't seen at match zoom in the real game.
