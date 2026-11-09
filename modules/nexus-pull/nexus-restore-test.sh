report() {
  ssh -T -o BatchMode=yes nexus "echo '$1 $(date -u +%Y-%m-%dT%H:%M:%SZ)' > /var/lib/nexus-backup/last-restore" || true
}
if systemctl start nexus-restore-check.service; then
  report restore-ok
else
  echo 'nexus-restore-test: the restore check failed; journalctl -u nexus-restore-check names the archive' >&2
  report restore-failed
  exit 1
fi
