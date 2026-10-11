state="${XDG_STATE_HOME:-$HOME/.local/state}/plato"
mkdir -p "$state"
if ! claude auth status >/dev/null 2>&1; then
  printf 'Plato: waiting for Claude sign-in on nexus (claude auth login); checking every 30 s\n'
  until claude auth status >/dev/null 2>&1; do sleep 30; done
fi
dir="$HOME/code"
mkdir -p "$dir"
cd "$dir"
name=Plato
args=(--dangerously-skip-permissions)
if [[ -s "$state/standby" ]]; then
  name="Plato standby"
  args+=(--append-system-prompt "$(cat "$state/standby")")
fi
idfile="$state/session-id"
id=$(cat "$idfile" 2>/dev/null || true)
if [[ -n "$id" && -f "$HOME/.claude/projects/${dir//\//-}/$id.jsonl" ]]; then
  exec claude --resume "$id" --remote-control "$name" "${args[@]}"
fi
id=$(cat /proc/sys/kernel/random/uuid)
printf '%s\n' "$id" >"$idfile"
exec claude --session-id "$id" --remote-control "$name" "${args[@]}"
