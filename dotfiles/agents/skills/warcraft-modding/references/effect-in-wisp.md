# Effect in Wisp

General Effect guidance is in `effect-development`; this file holds the Smashcraft-specific limits.

Effect is a deliberate part of Smashcraft's TypeScript application and host
tooling architecture. Prefer its services, typed failures, Schema boundaries,
scoped resource handling, and bounded concurrency where those abstractions
clarify a real application boundary. Keep deterministic frame simulation,
synchronized gameplay state, and other latency-sensitive code as small, pure
records and functions unless a measured design requires Effect there. Do not
put Effect imports in code compiled into synchronized game Lua: the current
Smashcraft toolchain probe (`effect@4.0.1`, TSTL 1.37.1) fails at module
resolution because Effect has no Lua source for TSTL to load. Use Effect in
Bun-hosted TypeScript services and tools. Reconsider map-Lua use only after an
actual TSTL compile and Warcraft Lua32 run both pass. Never import from the
vendored `repos/effect` tree; imports must resolve through the project's pinned
package dependency.
