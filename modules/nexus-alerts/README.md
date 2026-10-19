# nexus-alerts

`nexus-alert urgent|normal|socrates-test TEXT [TITLE] [CLICK]` publishes to the ntfy server on wg-nexus.
`urgent` is priority 5 (sound); `normal` and `socrates-test` are priority 2 (silent). There is no other
delivery path and nothing falls back to `urgent`.

## Alert policy

A phone push should mean "act now", so only these use `urgent`:

| Source | Event |
| --- | --- |
| nexus-checks | backup older than 26 h, root disk over 80%, unexpected SSH or console login, failed units (once per incident) |
| nexus-checks --lynis | hardening index drop or new lynis warning |
| nexus-vulnix | newly observed high/critical CVEs |
| watch-alerts (north model-watch) | disaster, weather or travel advisories for the configured location |
| supply-chain-scan | malware flagged in a tracked lockfile |

Everything else is quiet at priority 2 on `normal`: "healthy again" recovery notes, update, lock and
release-support age, vulnix scan errors, job-watch overdue and recovered jobs, the model-watch digest,
fixable supply-chain advisories and pace-control notices.

`nexus-notify@` only writes a failed unit's result and last log line to the journal; no unit has a
per-failure push. A failed unit reaches the phone through nexus-checks' deduplicated `units` check.
The laptop topic `socrates-laptop` (nexus-laptop-ntfy) carries only the daily window reminder with
its Open and Close buttons.
