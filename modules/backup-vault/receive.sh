cmd=${SSH_ORIGINAL_COMMAND:-}
case "$cmd" in
  list)
    for f in "$dir"/*.age; do
      [ -e "$f" ] || continue
      printf '%s\t%s\n' "$(basename "$f")" "$(stat -c %s "$f")"
    done
    ;;
  put\ *)
    name=${cmd#put }
    [[ $name =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,120}\.age$ ]] || { echo "refused: bad name" >&2; exit 2; }
    [ ! -e "$dir/$name" ] || { echo "refused: $name exists" >&2; exit 3; }
    used=$(du -sb "$dir" | cut -f1)
    [ "$used" -lt "$quota" ] || { echo "refused: vault over quota" >&2; exit 4; }
    tmp=$(mktemp "$dir/.incoming.XXXXXX")
    trap 'rm -f "$tmp"' EXIT
    head -c "$((max_file + 1))" > "$tmp"
    [ "$(stat -c %s "$tmp")" -le "$max_file" ] || { echo "refused: file too large" >&2; exit 5; }
    [ "$(head -c 21 "$tmp")" = "age-encryption.org/v1" ] || { echo "refused: not age ciphertext" >&2; exit 6; }
    ln "$tmp" "$dir/$name" || { echo "refused: $name exists" >&2; exit 3; }
    echo "stored $name"
    ;;
  *)
    echo "refused: only list and put NAME" >&2
    exit 1
    ;;
esac
