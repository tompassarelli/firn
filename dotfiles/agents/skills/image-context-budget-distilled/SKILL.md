---
name: image-context-budget-distilled
description: >-
  Inspect repeated screenshots or graphical sessions without accumulating image
  payloads in conversation history; recover from image-related request-size failures.
---

# Image context budget

Use disk captures and bounded text as the normal graphical development loop.
This governs inspection evidence, not images the user requested as deliverables.

## Inspect without attaching

Capture to an exact local file. Verify capture success and freshness before
using it; a failed capture leaves an older image, not fresh runtime evidence.
Use application state, accessibility/DOM data, logs, OCR, or pixel measurements
for the decision. For UI coordinates, OCR bounding boxes can preserve position
without an image attachment. Return only the relevant text or measurements.

Do not call `view_image`, emit `image(...)`, or forward screenshot content in
the routine capture loop. Do not print/serialize image tool results, data URLs,
base64, or binary bodies. Saving a capture does not require showing it in chat.
Keep large originals, recordings, and diagnostic sequences on disk; link an
artifact when the user needs it. Retrieve conversation history as text only.

## Exceptional visual inspection

Preview only when a specific decision depends on visual information that the
text/measurement path cannot establish, such as animation silhouette or clipping.
Name that decision before loading the image. Crop to the relevant region and
encode a small JPEG on disk first; inspect that exact file's encoded size.

Allow at most two inspection previews per conversation context, at most 128 KiB
of base64 image data each and 256 KiB cumulatively. Account for every image
returned by tools, including child reports, not just user-facing attachments.
Base64 alone costs `4 * ceil(file_bytes / 3)` bytes; duplicate representations
also count. These conservative limits are guardrails, not a proof that the
complete provider request fits. If prior image volume is unknown, use text only.
Never forward a full screenshot or repeatedly attach resized screenshots as
status evidence. User-requested image deliverables do not authorize a screenshot
stream for development inspection.

## After a request-size failure

Immediately switch the affected context to text-only inspection: no image
tools, inline images, base64, thumbnails, contact sheets, or image-bearing
history retrieval. Retain paths and conclusions in a short text handoff.
Use a supported compaction/context reset only when available; resume previews
only after the runtime confirms prior image content was removed. A smaller next
image, a new turn, a textual summary, or elapsed time does not shrink history.
Do not retry the oversized request unchanged or ask the user to repeat their work.
Continue authorized work through disk captures and text evidence.

For the evidence and scope behind these limits, read
[nixos-config:inspection policy notes](references/rationale.md) only when revising them.
