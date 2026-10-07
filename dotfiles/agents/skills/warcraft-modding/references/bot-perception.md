# Smashcraft bot perception and replay allocation

For Smashcraft CPU observation/history allocation, consume the shared immutable,
reference-counted snapshots in smashcraft:ts/src/game/match/botPerception.ts
(commit c3814aee): retain histories through `copyBotMemory` and release them
through `clearBotMemory`; never give one owner another owner's mutable history.
Stream the exact canonical checksum bytes through
smashcraft:ts/src/game/replay/canonical.ts and materialize replay text only on
request. In Lua32, 100 warmed four-fighter observation/history-copy samples
used 0.011 KB/frame versus the earlier 97.14 KB/frame; an equivalence sample
kept 1,300 observation strings and 10,000 number encodings identical. Regressions
live in smashcraft:ts/src/game/match/botReactionContracts.tests.ts and
smashcraft:ts/src/game/replay/canonical.tests.ts. Use the unchanged
`playable-bot-four` performance fixture for whole-frame acceptance. This
establishes the measured warmed allocation reduction, not flat memory across
matches or native handle lifetimes.
