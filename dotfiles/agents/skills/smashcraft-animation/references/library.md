# Animation reference library

This is an index of useful source material and original authoring decisions,
not a collection of redistributable game art. Sources were fetched on
2026-10-07. Video identities, official channel and descriptions were verified
from the returned YouTube player metadata. Unavailable captions do not justify
invented quotations or timestamps. The URLs open the actual reference videos;
the full clip ranges below are navigable ranges, not claims of a watched frame.

## Primary creator sources

| Source and usable range | Verified content and use | Scope/rights |
| --- | --- | --- |
| Masahiro Sakurai, [Damage Animations](https://www.youtube.com/watch?v=0xHE3ypX96U), 0:00–4:11 | Official description explicitly identifies damage animation as player feedback and emphasizes the workload of unique body types. Tom's observed Captain Falcon high/mid/low × small/medium/large example is the nine-pose brief; exact matrix timestamp remains to be annotated from playback. | Official Creating Games channel UCv1DvRY5PyHHt3KN9ghunuw. Video/thumbnail/game pixels copyrighted; link for study, no project redistribution. |
| Sakurai, [Breaking Down Attack Animations](https://www.youtube.com/watch?v=LewXWM7HDd8), 0:00–3:34 | Official description names lead-ins, attacks and follow-throughs as the fundamentals addressed. Use to block distinct preparation/action/recovery silhouettes. | Same official channel; copyrighted video, reference only. |
| Sakurai, [Follow-Throughs Make the Impact](https://www.youtube.com/watch?v=cIB0BUe6Ihk), 0:00–4:18 | Official description defines follow-through as the recovery after actions such as attacks and highlights how long that period can be. Fit visible recovery to Smashcraft's existing frame budget. | Same official channel; copyrighted video, reference only. |
| Sakurai, [Exaggerate to Make Up for Information Loss](https://www.youtube.com/watch?v=Ivwt37x-2EU), 0:00–2:28 | Verified title identifies exaggeration in response to lost visual information. Side-view separation and exaggerated silhouette are Smashcraft authoring decisions; no unverified quote or numerical rule is attributed to this clip. | Same official channel; copyrighted video, reference only. |
| Sakurai, [Always Keep Attack Collision in Mind](https://www.youtube.com/watch?v=rwwF_4blK-o) | Reference for contact alignment; link located in the official-channel search results. Verify the needed segment in playback before attributing a detailed claim. | Link-only discovery; copyrighted video. |
| Sakurai, [Eight Hit Stop Techniques](https://www.youtube.com/watch?v=tycbMSjDDLg) | Linked directly by the verified Damage Animations description. Pair with the written primary-author explanation below when examining stop-frame feedback. | Link-only discovery; copyrighted video. |
| Sakurai, [Hit Marks](https://www.youtube.com/watch?v=B-P4ysHSjCg) | Reference for hit-effect language. Located by official channel search; detailed cue timing still needs playback. | Link-only discovery; copyrighted video. |

### Primary-author written explanation, translated

[“Thinking About Hitstop,” Famitsu column 490–491, translated by Source Gaming](https://sourcegaming.info/2015/11/11/thoughts-on-hitstop-sakurais-famitsu-column-vol-490-1/)
is readable full text. The page explicitly labels the translation as fan use
and cautions it may not exactly reflect Sakurai. Attribute the translator as
well as the author; do not treat translated phrasing as a verified Japanese
quotation. The retrieved text supplies these specific claims:

- **Damage Vibration → Keeping Hurtboxes Stationary:** visual vibration is
  separated from stationary collision, so shaking does not make otherwise
  valid contacts miss.
- **Grounded = Horizontal, Aerial = Vertical:** ground shake runs side to
  side to avoid feet clipping into the floor; aerial shake runs vertically.
- **Adjusting Amplitude to Camera Distance:** larger visual displacement
  compensates for a farther camera.
- **Slowly Focusing the Vibration:** shake starts larger and diminishes over
  the precomputed freeze interval.
- **Other → Making Damage Look Painful:** an initial flinch transitions into
  a painful pose during hitstop; the historical example uses four frames.
  Tom delegated researched, move-appropriate transition timing in #181;
  his earlier 1–2 frames is guidance, not a fixed gate. Neither number is a
  claimed Melee fact. Promptly readable pain during the stop remains required.
- **Moving Slightly During Hitstop:** very slow attacker animation is described
  as presentation flavor, with the normal animation position restored on
  release. This supports separate presentation and simulation clocks, not a
  mandate to copy the particular technique.

Rights: article, translation and embedded images have no permissive reuse
license identified. Record factual summaries in original wording; retain
local fetched text privately; do not copy prose or images into shipped art.

## Melee action examples and interval definitions

| Reference | Exact factual scope | Authoring use and rights |
| --- | --- | --- |
| [Fox down aerial, SmashWiki revision 1940996](https://www.ssbwiki.com/index.php?title=Fox_(SSBM)/Down_aerial&oldid=1940996), Overview / Timing / displayed hitbox image | Describes an airborne downward drilling motion. Seven active pulses at display frames 5–6, 8–9, 11–12, 14–15, 17–18, 20–21 and 23–24. | Study body rotation, leading feet and repeated action; do not borrow damage or frame budget. Wiki text is CC BY-SA 4.0; original factual summaries here, no copied text. Nintendo image/GIF rights are separate and no redistribution license was established. |
| [Shieldstun, revision 2050074](https://www.ssbwiki.com/index.php?title=Shieldstun&oldid=2050074), introduction | Defender shieldstun occurs after hitlag, while attacker resumes their move recovery. | Separate stop and released shield response. CC BY-SA 4.0 text, factual summary only. This does not establish body hue. |
| [Hitlag, revision 2063427](https://www.ssbwiki.com/index.php?title=Hitlag&oldid=2063427), introduction and external links | Distinguishes the brief impact stop and links Sakurai's article/videos. | Use the creator article for visual claims; this is secondary corroboration. CC BY-SA 4.0 text. |
| [Hitstun, revision 2063426](https://www.ssbwiki.com/index.php?title=Hitstun&oldid=2063426), introduction | Describes the defender's inability to act after an attack and ties duration to knockback. | Separate hurt response after stop from impact freeze. CC BY-SA 4.0 text. No tint-timing claim. |

Smashcraft's existing factual corpus is the numerical source for timings:
smashcraft:references/melee-frame-data/records.jsonl and
smashcraft:docs/smash-melee-reference/. Existing measured shield contact is
smashcraft:docs/smash-melee-reference/slippi-ntsc-shield-contact.json;
damage is smashcraft:docs/smash-melee-reference/slippi-ntsc-grounded-damage.json.
Those numerical traces do not record pixel colors. Keep original/decompiled
code and proprietary animation assets out of implementation references.

## Original Smashcraft application decisions

These are authored standards, not claims that Nintendo uses exactly them:

- Drills: preparation → leading feet/blade → coordinated visible body turn →
  distinct exit. Whole-body participation distinguishes a drill from an
  effect spinning around an idle fighter. Check quarter-turn silhouettes.
- Rolls: tuck, rotate and re-establish support; simulation supplies travel.
  Get-up attacks sweep both directions where their active regions do.
- Grabs/throws: paired holder/victim blocking, stable contact, localized pummel,
  four directional releases and re-established support. Check differing body
  heights and mirrors, both facings; use the existing grab pair tool.
- Nine pain reactions: height controls the affected body region; intensity
  controls exaggeration. Preserve different silhouettes across all nine.
- Tint question: record adjacent frames for accepted hit and blocked hit,
  label contact, remaining stop, first released stun and first actionable
  frame from state, then sample body pixels away from sparks/shell. A single
  bright still cannot distinguish material tint from lighting/effect overlap.
  No hue policy is established by the sources retrieved here.

## Private visual resource and acquisition notes

Private cache: ~/.local/share/smashcraft-animation-reference/.
The official Damage Animations thumbnail is retained there as
damage-thumbnail.jpg (480×360, 40,507 bytes), solely for private reference.
It is not an animation-frame sequence and cannot establish timing.
Source URL: https://i.ytimg.com/vi/0xHE3ypX96U/hqdefault.jpg.
The linked Fox drill animation is retained privately at
~/.local/share/smashcraft-animation-reference/fox-down-air.gif (200×144).
Source URL:
https://ssb.wiki.gallery/images/thumb/a/a3/Fox_Down_Aerial_Hitbox_Melee.gif/200px-Fox_Down_Aerial_Hitbox_Melee.gif.
It is useful for the spinning-body/leading-feet sequence; the superimposed
hitboxes are the reference game's and are not a Smashcraft authoring template.
Nintendo animation pixels have no identified redistribution permission.
Keep every downloaded visual outside repositories and add its source,
observed timestamp/frame, rights and purpose to the private rights record.

The caption endpoint returned an automated-query rejection; no transcript
claim is made from it. Storyboard retrieval did not yield valid frame images.
Use supported playback or locally owned source recordings for exact visual
annotations; do not treat error HTML as an image or fabricate a timestamp.
URLs and primary-author written claims already support the authoring decisions;
the missing exact video segment is not a reason to delay usable roster repairs.
