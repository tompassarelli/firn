set -eu
path=$1
url=$2
export GIT_TERMINAL_PROMPT=0 GIT_CONFIG_NOSYSTEM=1 GIT_ASKPASS=false
parent=$(dirname "$path")
mkdir -p "$parent"
if [ -e "$path/.git" ]; then
  exec git -C "$path" -c credential.helper= fetch --prune origin
fi
if [ -e "$path" ]; then
  echo "agent-north-checkout: $path exists without a .git; leaving it untouched" >&2
  exit 1
fi
staging=$(mktemp -d "$parent/.checkout.XXXXXX")
trap 'rm -rf "$staging"' EXIT
git -c credential.helper= clone "$url" "$staging/clone"
mv "$staging/clone" "$path"
