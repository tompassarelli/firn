#!/usr/bin/env bash
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
repo_root=$(cd "$here/../.." && pwd)
scratch=$(mktemp -d -t north-stage-a.XXXXXX)
trap 'rm -rf "${scratch:?}"' EXIT

expr=$scratch/stage-a-eval.nix
cat >"$expr" <<'EOF'
{ repoRoot, stageA, socketActivation }:

let
  flake = builtins.getFlake ("path:" + repoRoot);
  system = builtins.currentSystem;
  pkgs = import flake.inputs.nixpkgs { inherit system; };
  lib = pkgs.lib;
  framPkg = pkgs.runCommand "fram-stage-a-fixture" { } ''
    mkdir -p "$out/libexec/fram" "$out/bin"
    printf '%s\n' '#!/bin/sh' 'exit 0' > "$out/bin/fram-daemon"
    printf '%s\n' '#!/bin/sh' 'exit 0' > "$out/bin/fram"
    chmod +x "$out/bin/fram-daemon" "$out/bin/fram"
  '';
  northPkg = pkgs.runCommand "north-stage-a-fixture" { } ''
    mkdir -p "$out/bin"
    for name in north north-mcp north-coord-sd-listen north-on-spawn \
      north-on-tooluse north-mark-delegated north-on-stop concern \
      north-stream-sync north-pinned north-effort; do
      printf '%s\n' '#!/bin/sh' 'exit 0' > "$out/bin/$name"
      chmod +x "$out/bin/$name"
    done
  '';
  codexPkg = pkgs.runCommand "codex-stage-a-fixture" { } ''
    mkdir -p "$out/bin"
    printf '%s\n' '#!/bin/sh' 'exit 0' > "$out/bin/codex"
    chmod +x "$out/bin/codex"
  '';
  inputs = {
    fram = {
      packages.${system}.default = framPkg;
      rev = "1111111111111111111111111111111111111111";
    };
    north.packages.${system} = {
      default = northPkg;
      codex = codexPkg;
    };
  };
  evaluated = lib.evalModules {
    specialArgs = { inherit pkgs inputs; };
    modules = [
      (import (repoRoot + "/modules/north-coord/default.nix"))
      (import (repoRoot + "/modules/north/default.nix"))
      ({ lib, ... }: {
        options = {
          assertions = lib.mkOption {
            type = lib.types.listOf lib.types.anything;
            default = [ ];
          };
          environment.systemPackages = lib.mkOption {
            type = lib.types.listOf lib.types.package;
            default = [ ];
          };
          environment.variables = lib.mkOption {
            type = lib.types.attrsOf lib.types.str;
            default = { };
          };
          home-manager.users = lib.mkOption {
            type = lib.types.attrsOf lib.types.anything;
            default = { };
          };
          systemd.sockets = lib.mkOption {
            type = lib.types.attrsOf lib.types.anything;
            default = { };
          };
          systemd.services = lib.mkOption {
            type = lib.types.attrsOf lib.types.anything;
            default = { };
          };
          systemd.targets = lib.mkOption {
            type = lib.types.attrsOf lib.types.anything;
            default = { };
          };
          myConfig.modules.users.username = lib.mkOption { type = lib.types.str; };
          myConfig.modules.users.homeDir = lib.mkOption { type = lib.types.str; };
        };
        config = {
          myConfig.modules.users.username = "fixture";
          myConfig.modules.users.homeDir = "/tmp/north-stage-a-fixture";
          myConfig.modules.north.enable = true;
          myConfig.modules.north-coord.enable = true;
          myConfig.modules.north-coord.socketActivation = socketActivation;
          myConfig.modules.north-coord.stageATelemetryPartition = stageA;
        };
      })
    ];
  };
  cfg = evaluated.config;
  attr = set: name: builtins.hasAttr name set;
  coord = cfg.systemd.services.north-coord;
  telemetry = cfg.systemd.services.north-telemetry-coord or { };
  coordSocket = cfg.systemd.sockets.north-coord or { };
  telemetrySocket = cfg.systemd.sockets.north-telemetry-coord or { };
  pair = cfg.systemd.targets.north-coord-pair or { };
  northWrapper =
    lib.findFirst (pkg: lib.getName pkg == "north") null
      cfg.environment.systemPackages;
in
pkgs.writeText "north-stage-a-${if stageA then "on" else "off"}" (
  lib.concatStringsSep "\n" [
    "assertion=${lib.boolToString (builtins.all (item: item.assertion) cfg.assertions)}"
    "coord-socket=${lib.boolToString (attr cfg.systemd.sockets "north-coord")}"
    "telemetry-socket=${lib.boolToString (attr cfg.systemd.sockets "north-telemetry-coord")}"
    "coord-descriptor=${coordSocket.socketConfig.FileDescriptorName or "unset"}"
    "telemetry-descriptor=${telemetrySocket.socketConfig.FileDescriptorName or "unset"}"
    "coord-socket-part-of=${lib.concatStringsSep "," (coordSocket.partOf or [ ])}"
    "telemetry-socket-part-of=${lib.concatStringsSep "," (telemetrySocket.partOf or [ ])}"
    "coord-socket-wanted-by=${lib.concatStringsSep "," (coordSocket.wantedBy or [ ])}"
    "telemetry-socket-wanted-by=${lib.concatStringsSep "," (telemetrySocket.wantedBy or [ ])}"
    "coord-socket-restart-if-changed=${lib.boolToString (coordSocket.restartIfChanged or false)}"
    "coord-socket-stop-if-changed=${lib.boolToString (coordSocket.stopIfChanged or false)}"
    "telemetry-socket-restart-if-changed=${lib.boolToString (telemetrySocket.restartIfChanged or false)}"
    "telemetry-socket-stop-if-changed=${lib.boolToString (telemetrySocket.stopIfChanged or false)}"
    "telemetry-service=${lib.boolToString (attr cfg.systemd.services "north-telemetry-coord")}"
    "pair-target=${lib.boolToString (attr cfg.systemd.targets "north-coord-pair")}"
    "coord-part-of=${lib.concatStringsSep "," (coord.partOf or [ ])}"
    "telemetry-part-of=${lib.concatStringsSep "," (telemetry.partOf or [ ])}"
    "coord-restart-if-changed=${lib.boolToString coord.restartIfChanged}"
    "coord-stop-if-changed=${lib.boolToString coord.stopIfChanged}"
    "telemetry-restart-if-changed=${lib.boolToString (telemetry.restartIfChanged or false)}"
    "telemetry-stop-if-changed=${lib.boolToString (telemetry.stopIfChanged or false)}"
    "pair-wants=${lib.concatStringsSep "," (pair.wants or [ ])}"
    "coord-requires=${lib.concatStringsSep "," (coord.requires or [ ])}"
    "telemetry-requires=${lib.concatStringsSep "," (telemetry.requires or [ ])}"
    "coord-exec=${coord.serviceConfig.ExecStart}"
    "telemetry-exec=${telemetry.serviceConfig.ExecStart or ""}"
    "partition=${cfg.environment.variables.NORTH_TELEMETRY_PARTITION or "unset"}"
    "telemetry-port=${cfg.environment.variables.NORTH_TELEMETRY_PORT or "unset"}"
    "north-wrapper=${toString northWrapper}"
  ] + "\n")
EOF

cache=$scratch/cache
mkdir -p "$cache"
build_case() {
  local stage_a=$1 socket_activation=$2
  XDG_CACHE_HOME=$cache nix build \
    --impure --no-link --print-out-paths \
    --expr "import $expr { repoRoot = \"$repo_root\"; stageA = $stage_a; socketActivation = $socket_activation; }"
}

off=$(build_case false true)
grep -Fxq 'assertion=true' "$off"
grep -Fxq 'coord-socket=true' "$off"
grep -Fxq 'telemetry-socket=false' "$off"
grep -Fxq 'coord-socket-part-of=' "$off"
grep -Fxq 'coord-socket-wanted-by=sockets.target' "$off"
grep -Fxq 'coord-socket-restart-if-changed=false' "$off"
grep -Fxq 'coord-socket-stop-if-changed=false' "$off"
grep -Fxq 'telemetry-service=false' "$off"
grep -Fxq 'pair-target=false' "$off"
grep -Fxq 'coord-restart-if-changed=false' "$off"
grep -Fxq 'coord-stop-if-changed=false' "$off"
grep -Fxq 'partition=unset' "$off"
grep -Fxq 'telemetry-port=unset' "$off"
off_wrapper=$(sed -n 's/^north-wrapper=//p' "$off")
if grep -Fq 'NORTH_TELEMETRY_PARTITION=1' "$off_wrapper/bin/north"; then
  echo "Stage-A option-off wrapper unexpectedly enables partition routing" >&2
  exit 1
fi

on=$(build_case true true)
grep -Fxq 'assertion=true' "$on"
grep -Fxq 'coord-socket=true' "$on"
grep -Fxq 'telemetry-socket=true' "$on"
grep -Fxq 'coord-descriptor=north-coord' "$on"
grep -Fxq 'telemetry-descriptor=north-coord' "$on"
grep -Fxq 'coord-socket-part-of=' "$on"
grep -Fxq 'telemetry-socket-part-of=' "$on"
grep -Fxq 'coord-socket-wanted-by=sockets.target' "$on"
grep -Fxq 'telemetry-socket-wanted-by=sockets.target' "$on"
grep -Fxq 'coord-socket-restart-if-changed=false' "$on"
grep -Fxq 'coord-socket-stop-if-changed=false' "$on"
grep -Fxq 'telemetry-socket-restart-if-changed=false' "$on"
grep -Fxq 'telemetry-socket-stop-if-changed=false' "$on"
grep -Fxq 'telemetry-service=true' "$on"
grep -Fxq 'pair-target=true' "$on"
grep -Fxq 'coord-part-of=north-coord-pair.target' "$on"
grep -Fxq 'telemetry-part-of=north-coord-pair.target' "$on"
grep -Fxq 'coord-restart-if-changed=false' "$on"
grep -Fxq 'coord-stop-if-changed=false' "$on"
grep -Fxq 'telemetry-restart-if-changed=false' "$on"
grep -Fxq 'telemetry-stop-if-changed=false' "$on"
grep -Fq 'north-coord.socket' "$on"
grep -Fq 'north-telemetry-coord.socket' "$on"
grep -Fq 'north-coord.service' "$on"
grep -Fq 'north-telemetry-coord.service' "$on"
grep -Fxq 'partition=1' "$on"
grep -Fxq 'telemetry-port=7978' "$on"
grep -Fq '/bin/north-coord-runtime start' "$on"
grep -Fq '/bin/north-telemetry-coord-runtime start' "$on"
on_wrapper=$(sed -n 's/^north-wrapper=//p' "$on")
grep -Fq 'export NORTH_TELEMETRY_PARTITION=1' "$on_wrapper/bin/north"
grep -Fq 'export NORTH_TELEMETRY_PORT=7978' "$on_wrapper/bin/north"
grep -Fq 'FRAM_TELEMETRY_LOG=/tmp/north-stage-a-fixture/.local/state/north/telemetry.log' \
  "$on_wrapper/bin/north"

invalid=$(build_case true false)
grep -Fxq 'assertion=false' "$invalid"

grep -Fq 'unset FRAM_TELEMETRY_LOG NORTH_TELEMETRY_PARTITION NORTH_TELEMETRY_PORT' \
  "$here/north-coord-runtime"
# Assert the literal runtime command.
# shellcheck disable=SC2016
grep -Fq 'systemctl restart "$restart_systemd_unit"' \
  "$here/north-coord-runtime"
# Assert the literal runtime assignment.
# shellcheck disable=SC2016
grep -Fq 'NORTH_COORD_SYSTEMD_UNIT="$corpus_systemd_unit"' \
  "$here/north-coord-runtime"

echo "ok: Stage-A is dormant by default, owns two sockets/writers when enabled, propagates clients, and restarts as one pair"
