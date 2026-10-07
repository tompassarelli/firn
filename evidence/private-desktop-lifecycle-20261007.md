# Private desktop kill and relaunch, 7 October 2026

Owning check: [Wisp #37](https://github.com/tompassarelli/wisp/issues/37), original last box: kill one desktop, launch another, and leave no stale runtime folder.

Measured launcher: dotfiles/agents/skills/private-desktop-development/scripts/private-desktop.sh, Git blob c6f175cda5a6dc896154f525e77d66395ca26341. Both bare desktops used 640×480 hardware rendering, without Warcraft, through separate finite moderate capacity scopes. Admission protected CPU pressure was 0.00% and 0.18%.

1. Start desktop private-desktop.knvGBjWX, record its launcher and direct-child PIDs, then SIGKILL its exact launcher PID. The scope ended with the expected exit 137 and RELEASED lease d7eeb343-7aa4-4e37-b5e6-e1516c7b276c; its remaining processes were stopped by the scope.
2. Start desktop private-desktop.2YW7b8NY. Startup acquired the crashed session's free lock, removed its runtime files and active marker, and saved its logs on disk. The replacement command checked the missing old folder and retained logs, then exited normally. Its scope returned exit 0 and RELEASED lease e9f22fc8-7e48-4a9e-aee3-a9c3107bf155.

| Observation | Result |
| --- | --- |
| Ended runtime folders absent | 2/2 |
| Ended active markers absent | 2/2 |
| Ended logs preserved outside runtime tmpfs | 2/2 |
| Recorded crashed-session processes remaining | 0/4 |
| Runtime bytes retained by these ended sessions | 0 |

Logs were saved under the user's state/private-desktop directory. Existing peer folders were left untouched; recovery requires the launcher's ownership marker and a free session lock. The shared disk VNC environment from 6dd8268a remained reusable.

Source checks: shell syntax, existing private-desktop-capture.test.sh and skill frontmatter validation PASS. The active agent projection is updated with agents sync after publication.
