#!/usr/bin/env bash
set -euo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"

environment=$(nix-instantiate --eval --strict --json --expr "
  let
    lib = {
      inherit (builtins) concatStringsSep listToAttrs;
      mkIf = condition: value: if condition then value else { };
      mkEnableOption = _: { };
      mkOption = _: { };
      types = { listOf = _: { }; str = { }; };
      makeBinPath = paths: builtins.concatStringsSep \":\" (map (path: path + \"/bin\") paths);
      nameValuePair = name: value: { inherit name value; };
    };
    module = import $REPO/modules/north-land/default.nix {
      inherit lib;
      config.myConfig.modules = {
        north-land = { enable = true; repositories = [ \"north\" ]; };
        users = { username = \"tom\"; homeDir = \"/home/tom\"; };
      };
      pkgs = builtins.listToAttrs (map (name: { inherit name; value = \"/\" + name; }) [ \"bash\" \"bun\" \"coreutils\" \"git\" \"gnutar\" \"nix\" \"openssh\" \"rsync\" \"systemd\" \"util-linux\" ]);
      northBin = \"/north/bin\";
    };
    services = (module.config.home-manager.users.tom { }).systemd.user.services;
  in map (name: services.\${name}.Service.Environment) [ \"north-land@north\" \"north-land-rest\" ]
")

slices=$(jq -r '[.[] | map(select(startswith("NORTH_LAND_RUNNER_SLICE="))) | join(" ")] | join(",")' <<<"$environment")
[ "$slices" = "NORTH_LAND_RUNNER_SLICE=agent.slice,NORTH_LAND_RUNNER_SLICE=agent.slice" ] || { printf 'a lander does not start its after-landing runner outside its own cgroup, so a lander restart kills the run in flight: %s\n' "$slices" >&2; exit 1; }
echo "north-land: every lander starts its after-landing runner in agent.slice"
