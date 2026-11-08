vault_ssh=(ssh -T -i "$key" -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=20 "vault@$vault_host")
box_sftp=(sftp -P "$box_port" -i "$box_key" -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=20 "$box_user@$box_host")
send_vault() {
  if grep -qxF "$1" <<<"$remote"; then return 0; fi
  "${vault_ssh[@]}" "put $1" < "$2"
}
send_box() {
  printf 'put %s %s.part\nrename %s.part %s\n' "$2" "$1" "$1" "$1" | "${box_sftp[@]}" -b - > /dev/null
}
ship() {
  local sent=$out/.sent/$1 f name
  mkdir -p "$sent"
  if [ "$1" = vault ]; then remote=$("${vault_ssh[@]}" list | cut -f1); fi
  for f in "$out"/*.age; do
    [ -e "$f" ] || continue
    name=$(basename "$f")
    if [ -e "$sent/$name" ]; then continue; fi
    "send_$1" "$name" "$f"
    touch "$sent/$name"
  done
  find "$sent" -type f -mtime "+$keep_days" -delete
  echo "state-backup-push: $(find "$sent" -type f | wc -l) archives sent to $1"
}
destinations=(vault)
if [ -n "$box_host" ]; then destinations+=(box); fi
failed=0
for dest in "${destinations[@]}"; do
  ship "$dest" || { echo "state-backup-push: $dest failed" >&2; failed=1; }
done
date -u +%Y-%m-%dT%H:%M:%SZ > "$out/last-push"
exit "$failed"
