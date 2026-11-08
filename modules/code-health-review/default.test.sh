#!/usr/bin/env bash
set -euo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"

path=$(nix-instantiate --eval --strict --json --expr "
  let
    lib = {
      mkIf = condition: value: if condition then value else { };
      mkEnableOption = _: { };
      makeBinPath = paths: builtins.concatStringsSep \":\" (map (path: path + \"/bin\") paths);
    };
    module = import $REPO/modules/code-health-review/default.nix {
      inherit lib;
      config.myConfig.modules = {
        code-health-review.enable = true;
        users = { username = \"tom\"; homeDir = \"/home/tom\"; };
      };
      pkgs.git = \"/git\";
      jobRun = name: cmd: cmd;
      northBin = \"/north/bin\";
      unitPath = \"/unit/bin\";
    };
  in builtins.head (module.config.home-manager.users.tom { }).systemd.user.services.code-health-review.Service.Environment
" | jq -r .)

case ":${path#PATH=}:" in
*:/git/bin:*) echo "code-health-review: the tick finds git to fetch each enrolled repo" ;;
*) printf 'the code-health tick cannot fetch without git on %s\n' "$path" >&2; exit 1 ;;
esac
