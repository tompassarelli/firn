host=$vault_host
ssh_cmd=(ssh -T -i "$key" -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=20 "vault@$host")
sent=$out/.sent
mkdir -p "$sent"
remote=$("${ssh_cmd[@]}" list | cut -f1)
for f in "$out"/*.age; do
  [ -e "$f" ] || continue
  name=$(basename "$f")
  if [ -e "$sent/$name" ]; then continue; fi
  if ! grep -qxF "$name" <<<"$remote"; then
    "${ssh_cmd[@]}" "put $name" < "$f"
  fi
  touch "$sent/$name"
done
find "$sent" -type f -mtime "+$keep_days" -delete
date -u +%Y-%m-%dT%H:%M:%SZ > "$out/last-push"
echo "state-backup-push: $(find "$sent" -type f | wc -l) archives held on $host"
