# LAN pool frame caps and discovery socket

Read with wisp:docs/lan.md when tuning pool contention or the lobby discovery socket.

For pool contention, `--fps N` varies only foreground/background frame caps;
keep the map and active script fixed and compare per-client CPU/GPU cost,
protected CPU pressure, parity and game time before changing a default cap.
Consume Wisp's discovery lifecycle mitigation (wisp commit 2aaae0b): close
the lobby UDP discovery socket when countdown starts; gameplay continues on
TCP. With Bun 1.3.13, an isolated two-second ECONNREFUSED polling sample
consumed 1.664 CPU-seconds with the socket retained and 0.0028 after close
(about 600× less isolated socket cost). The old pair host used 1.11 cores;
fleet savings require a controlled pair-agent restart and measurement, so
do not extrapolate the isolated ratio to the fleet. This is a bounded Wisp
lifecycle mitigation, not a Bun root repair. When comparing this mitigation,
keep the 60 fps cap and 2 ms autopsy polling unchanged. Procedure and
regression are in wisp:docs/lan.md and wisp:test/lan.test.ts.
