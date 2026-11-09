set -eu

bin="$HOME/.local/bin"
firn="$HOME/.local/share/firn/bin"
north="$HOME/.local/share/north/bin"
shims="$HOME/.local/state/north/current/shims/bin"

managed() {
  case "$(readlink "$1" 2>/dev/null)" in
    "$shims"/* | "$firn"/* | "$north"/*) return 0 ;;
    *) return 1 ;;
  esac
}

if [ -L "$bin" ]; then
  rm "$bin"
fi
mkdir -p "$bin"

declare -A seen
for dir in "$firn" "$north"; do
  [ -d "$dir/" ] || continue
  for src in "$dir"/*; do
    [ -e "$src" ] || [ -L "$src" ] || continue
    [ -x "$src" ] || continue
    name="${src##*/}"
    [ -z "${seen[$name]:-}" ] || continue
    seen[$name]=1
    if [ "$dir" = "$north" ] && { [ "$name" = cargo ] || [ "$(readlink "$src")" = cargo ]; }; then
      src="$shims/$name"
    fi
    dst="$bin/$name"
    if [ ! -e "$dst" ] && [ ! -L "$dst" ]; then
      ln -s "$src" "$dst"
    elif managed "$dst" && [ "$(readlink "$dst")" != "$src" ]; then
      ln -sfn "$src" "$dst"
    fi
  done
done

for dst in "$bin"/*; do
  case "$(readlink "$dst" 2>/dev/null)" in "$shims"/*) continue ;; esac
  if [ -L "$dst" ] && [ ! -e "$dst" ] && managed "$dst"; then
    rm "$dst"
  fi
done
