dest=$1
key="${CREDENTIALS_DIRECTORY:?}/age-key"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

newest() { find "$dest" -maxdepth 1 -name "$1" -printf '%T@ %p\n' | sort -n | tail -n1 | cut -d' ' -f2-; }
checked=0
for kind in 'state-full-*.age' 'state-incr-*.age'; do
  f=$(newest "$kind")
  [ -n "$f" ] || continue
  age -d -i "$key" "$f" | zstd -q -t || { echo "archive $(basename "$f") failed" >&2; exit 1; }
  echo "archive ok: $(basename "$f")"
  checked=$((checked + 1))
done
for name in $(find "$dest" -maxdepth 1 -name 'ledger-*.age' -printf '%f\n' | sed -E 's/-[0-9]{8}T[0-9]{6}Z\.sql\.zst\.age$//' | sort -u); do
  f=$(newest "$name-*.sql.zst.age")
  rm -f "$work/restore.db"
  age -d -i "$key" "$f" | zstd -q -d | sqlite3 "$work/restore.db" || { echo "ledger $(basename "$f") did not restore" >&2; exit 1; }
  result=$(sqlite3 "$work/restore.db" 'pragma integrity_check')
  [ "$result" = ok ] || { echo "ledger $(basename "$f") integrity_check: $result" >&2; exit 1; }
  echo "ledger integrity ok: $(basename "$f") ($(sqlite3 "$work/restore.db" "select count(*) from sqlite_master where type='table'") tables)"
  checked=$((checked + 1))
done
[ "$checked" -gt 0 ] || { echo "no backups found in $dest" >&2; exit 1; }
