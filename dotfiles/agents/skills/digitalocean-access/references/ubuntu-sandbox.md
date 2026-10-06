# Ubuntu sandbox repair

## Observed failure and owning repair

On the recorded Ubuntu 24.04 host, missing distribution bubblewrap caused
`bwrap: loopback: Failed RTM_NEWADDR: Operation not permitted`. The owning
repair was the Ubuntu `bubblewrap` and `apparmor-profiles` packages, followed
by installing Ubuntu's
/usr/share/apparmor/extra-profiles/bwrap-userns-restrict at
/etc/apparmor.d/bwrap-userns-restrict and loading that exact profile with
`apparmor_parser -r`. The global
`kernel.apparmor_restrict_unprivileged_userns=1` remains enabled. Verify an
actual sandboxed command through the intended app-server after repair; do not
disable AppArmor globally or bypass Codex sandboxing.

## Apply only to the matching failure

This is a specific distribution/AppArmor repair, not a general recipe for every
permission error. Verify the missing package/profile and failing sandbox call
before applying it. Keeping the global user-namespace restriction enabled
preserves the host boundary; an unsandboxed successful command would not prove
the repaired sandbox works.
