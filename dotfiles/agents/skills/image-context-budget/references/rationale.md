# Inspection policy notes

The operator requested a skill and persistent instructions after repeated
Warcraft development sessions exceeded the upstream websocket request limit.
Observed errors rejected requests of 28,330,279 and 17,679,086 bytes against a
15,728,640-byte limit. The second failure occurred after promising smaller
captures, then repeatedly forwarding 960-pixel previews. Per-image resizing did
not prevent cumulative history growth.

The adopted rule separates evidence acquisition from conversation attachment.
Disk captures still establish UI/rendering facts; OCR, coordinates, logs, and
pixel measurements allow ordinary navigation without inserting images. A visual
judgment such as blade readability may need a carefully bounded preview when
the context permits one. A full recording belongs in an artifact, not the prompt.

The two-preview/256-KiB encoded budget leaves room for other request content; it
is an intentionally conservative inspection budget, not a measured provider
limit or guarantee. Unknown historical volume means no additional previews.
After an actual payload rejection, even a tiny new thumbnail adds to the
already oversized history, so previews remain disabled until removal is verified.

Matching case: repeated two-client lobby navigation uses fresh disk captures,
OCR text/bounding boxes, and small factual updates. A failed capture cannot
make an older file current. Animation review can use a cropped preview only
within the cumulative budget and outside a rejected context.

Nonmatching case: a user asks for an exported illustration or scientific figure.
Creating and linking that requested artifact remains allowed; the inspection
policy does not ban visual deliverables or require OCR for visual judgments.

Deliberate omissions: no provider-specific request-size promise, automatic
transcript deletion, screenshot watcher, new background service, or claim that
an instruction is mechanically enforced. No compaction tool was exposed during
the reported session; prose could not prove that prior images had been removed.
