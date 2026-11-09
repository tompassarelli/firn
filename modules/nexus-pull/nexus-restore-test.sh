dest=$HOME/backups/nexus
work=$(mktemp -d -p "${XDG_RUNTIME_DIR:?}")
trap 'rm -rf "$work"' EXIT
chmod 700 "$work"
report() {
  ssh -T -o BatchMode=yes nexus "echo '$1 $(date -u +%Y-%m-%dT%H:%M:%SZ)' > /var/lib/nexus-backup/last-restore" || true
}
fail() { echo "nexus-restore-test: $1" >&2; report restore-failed; exit 1; }
sudo -n cat /var/lib/sops-nix/key.txt | tee "$work/key" >/dev/null

newest() { find "$dest" -maxdepth 1 -name "$1" -printf '%T@ %p\n' | sort -n | tail -n1 | cut -d' ' -f2-; }
checked=0
for kind in 'state-full-*.age' 'state-incr-*.age'; do
  f=$(newest "$kind")
  [ -n "$f" ] || continue
  age -d -i "$work/key" "$f" | zstd -q -t || fail "archive $(basename "$f") failed"
  echo "archive ok: $(basename "$f")"
  checked=$((checked + 1))
done
for name in $(find "$dest" -maxdepth 1 -name 'ledger-*.age' -printf '%f\n' | sed -E 's/-[0-9]{8}T[0-9]{6}Z\.sql\.zst\.age$//' | sort -u); do
  f=$(newest "$name-*.sql.zst.age")
  rm -f "$work/restore.db"
  age -d -i "$work/key" "$f" | zstd -q -d | sqlite3 "$work/restore.db" || fail "ledger $(basename "$f") did not restore"
  result=$(sqlite3 "$work/restore.db" 'pragma integrity_check')
  [ "$result" = ok ] || fail "ledger $(basename "$f") integrity_check: $result"
  echo "ledger integrity ok: $(basename "$f") ($(sqlite3 "$work/restore.db" "select count(*) from sqlite_master where type='table'") tables)"
  checked=$((checked + 1))
done
[ "$checked" -gt 0 ] || fail "no backups found in $dest"
report restore-ok
