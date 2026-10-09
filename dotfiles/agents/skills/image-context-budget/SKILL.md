---
name: image-context-budget
description: >-
  Inspect repeated screenshots or graphical sessions without accumulating image
  payloads in conversation history; recover from image-related request-size failures.
---

# Image context

- Capture to exact local files and verify success/freshness before inspection.
- Use application state, DOM/accessibility, logs, OCR boxes or pixel measurements in routine capture loops.
- Keep originals/recordings on disk and retrieve history as text.
- Name a visual decision that text cannot settle before using view_image or image output.
- Crop the relevant region to a small JPEG and check its encoded size.
- Allow at most 2 previews/context, 128 KiB base64 each and 256 KiB total, counting child/tool duplicates at `4 * ceil(file_bytes / 3)`.
- Use text only when prior image volume is unknown.
- Keep user-requested image deliverables separate from development inspection.
- Switch an oversized context immediately to text-only paths/conclusions; resume previews only after the runtime confirms prior image content was removed.
- Never retry the oversized request unchanged or ask Tom to repeat work.

Use [inspection notes](references/rationale.md) only when revising these limits.
