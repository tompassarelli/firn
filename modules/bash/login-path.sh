case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *) export PATH="$HOME/.local/bin:$PATH" ;;
esac

for d in "$HOME/.local/share/firn/bin" "$HOME/.local/share/north/bin" "$HOME/.local/share/south/bin"; do
  case ":$PATH:" in
    *":$d:"*) ;;
    *) export PATH="$PATH:$d" ;;
  esac
done
