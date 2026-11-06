#!/usr/bin/env bash
set -euo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"

units=$(nix-instantiate --eval --strict --json --expr "
  let
    lib = {
      inherit (builtins) concatStringsSep;
      mkIf = condition: value: if condition then value else { };
      mkEnableOption = _: { };
      mkOption = _: { };
      types = { listOf = _: { }; str = { }; };
      makeBinPath = paths: concatStringsSep \":\" (map (path: path + \"/bin\") paths);
    };
    inherit (builtins) concatStringsSep;
    module = import $REPO/modules/ssh-masters/default.nix {
      inherit lib;
      config.myConfig.modules = {
        ssh-masters = { enable = true; hosts = [ \"nexus\" \"gex45\" \"ccx33\" ]; };
        users.username = \"tom\";
      };
      pkgs = { bash = \"/bash\"; coreutils = \"/coreutils\"; openssh = \"/openssh\"; systemd = \"/systemd\"; };
      northBin = \"/north/bin\";
    };
    user = (module.config.home-manager.users.tom { }).systemd.user;
  in {
    masters = builtins.filter (name: builtins.substring 0 11 name == \"ssh-master-\" && name != \"ssh-master-probe\") (builtins.attrNames user.services);
    probe = user.services.ssh-master-probe.Service.ExecStart;
    path = builtins.head user.services.ssh-master-probe.Service.Environment;
    every = user.timers.ssh-master-probe.Timer.OnUnitInactiveSec;
  }
")

masters=$(jq -r '.masters | sort | join(" ")' <<<"$units")
probe=$(jq -r .probe <<<"$units")
every=$(jq -r .every <<<"$units")
path=$(jq -r .path <<<"$units")

[ "$masters" = "ssh-master-ccx33 ssh-master-gex45 ssh-master-nexus" ] || { printf 'master units: %s\n' "$masters" >&2; exit 1; }
[ "$probe" = "/north/bin/north ssh-master probe nexus gex45 ccx33" ] || { printf 'the probe does not cover every master host: %s\n' "$probe" >&2; exit 1; }
[ "$path" = "PATH=/bash/bin:/coreutils/bin:/openssh/bin:/systemd/bin" ] || { printf 'the probe cannot start north'"'"'s bash wrapper with %s\n' "$path" >&2; exit 1; }
[ "$every" = "1min" ] || { printf 'the probe runs every %s, not every minute\n' "$every" >&2; exit 1; }
echo "ssh-masters: the probe covers every master host each minute"
