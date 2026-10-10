---
name: smashcraft-stage-design
description: >-
  Design, dress and judge a Smashcraft stage's look: backdrop, scenery bands,
  set pieces, the deck's underside, water, sky, light and fighter contrast, in
  Classic and Definitive. Use for any stage art, stage composition or stage
  look issue, a new stage, or a stage review.
grounded: 2026-10-09
written: 2026-10-09
metadata:
  kind: domain
---

# Smashcraft stage design

- Apply the rules and limits in smashcraft:docs/design/stage-art.md and smashcraft:docs/design/visual-quality.md.
- Reuse existing stage lighting packages, contrast rows and asset-family storage through `bun wisp inputs add`.
- Read ~/.local/share/smashcraft-stage-references/README.md and view its images before changing art.
- Use Nintendo reference captures only for judgment without committing, importing or tracing them.
- Choose a reference matching the stage's layout: horizon band, close set pieces, enclosed arena, large object or floating island over vivid sky.
- Inspect `00-anti-smashcraft-tomb-0.0.100.png` as the rejected empty composition.
- Fill the middle frame with scenery, close set pieces, enclosure, stage mass or vivid sky.
- Seat the deck in surrounding scenery, water, structure or a modeled underside mass rather than a flat tiled texture.
- Make the landmark recognizable at match zoom close behind the deck.
- Render water as a lighter, rippled full-width surface at its actual height with submerged supports, entry splashes and visible swimming.
- Keep fighters and the fighting area brightest while reducing saturation and contrast with depth.
- Pass the existing fighter contrast rows.
- Compose platforms, deck and scenery as one place with consistent light and native Warcraft III assets first.
- Complete Classic and Definitive scenes at both camera extremes with side platforms inside the frame and no clipped edges.
- Judge near and far match views at 16:9 beside the chosen reference.
- Measure below-horizon backdrop-only pixels against the limit in visual-quality.md.
- Capture Wisp frames followed by one native LAN-pool capture.
- Confirm graphics-mode changes took effect by checking that Classic and Definitive frames differ.
- Inspect grayscale frames at about 320 pixels wide for readable fighters and ledges without large empty fields.
- Post before/after images beside the reference on the issue and name the reference and rule served by each change.
- Preserve collision, blast zones, platform positions and frame cost while fitting art to geometry.
- Judge composition visually in addition to contrast checks.
- Show Tom the result at match zoom in the real game before shipping.
