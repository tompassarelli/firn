out=/var/lib/nexus-backup
stamp=$(date -u +%Y%m%dT%H%M%SZ)
umask 077
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
recipient_args=()
for r in "${recipients[@]}"; do recipient_args+=(-r "$r"); done

tarq() { tar "$@" 2>/dev/null || [ $? -eq 1 ]; }

seal() {
  zstd -q -19 -T0 | age "${recipient_args[@]}" -o "$out/$1.tmp"
  mv "$out/$1.tmp" "$out/$1"
}

while IFS= read -r -d '' db; do
  name=$(basename "$(dirname "$db")")-$(basename "$db" .db)
  sqlite3 "$db" ".backup '$work/copy.db'"
  sqlite3 "$work/copy.db" .dump | seal "ledger-$name-$stamp.sql.zst.age"
  rm -f "$work/copy.db"
done < <(find "$HOME/.local/state" -name threads.db -type f -print0)

existing=()
for p in "${paths[@]}"; do if [ -e "$p" ]; then existing+=("$p"); fi; done
marker=$out/.incr-marker
last_full=$(find "$out" -maxdepth 1 -name 'state-full-*.age' -mtime -7 | head -n1)
touch "$work/next-marker"
if [ "${#existing[@]}" -gt 0 ]; then
  if [ -z "$last_full" ] || [ ! -e "$marker" ] || [ "$(date +%u)" = 7 ]; then
    tarq -cf - --ignore-failed-read "${existing[@]}" | seal "state-full-$stamp.tar.zst.age"
  else
    find "${existing[@]}" -type f -newer "$marker" -print0 > "$work/changed" 2>/dev/null || true
    tarq -cf - --null --no-recursion --ignore-failed-read -T "$work/changed" | seal "state-incr-$stamp.tar.zst.age"
  fi
fi
cp -p "$work/next-marker" "$marker"

find "$out" -maxdepth 1 -name '*.age' -mtime +35 -delete
find "$out" -maxdepth 1 -name '*.tmp' -delete
date -u +%Y-%m-%dT%H:%M:%SZ > "$out/last-ok"
