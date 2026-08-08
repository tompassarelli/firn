{ config, lib, pkgs, inputs, ... }:

let
  homeDir = config.myConfig.modules.users.homeDir;
  stageA = config.myConfig.modules.north-coord.stageATelemetryPartition;
  clientEnvironment = if stageA then ''
    export NORTH_TELEMETRY_PARTITION=1
    export NORTH_TELEMETRY_PORT=7978
    export FRAM_TELEMETRY_LOG=${homeDir}/.local/state/north/telemetry.log
  '' else "";
  northPkg = "/home/tom/code/north/main";
  northEnv = inputs.north.packages."${pkgs.stdenv.hostPlatform.system}".north-env;
  codexPkg = inputs.north.packages."${pkgs.stdenv.hostPlatform.system}".codex;
  liveInputs = with pkgs; [ bash coreutils git babashka bun jq ];
  northRuntimeOwnerGuard = pkgs.writeShellApplication {
    name = "north-runtime-owner-guard";
    runtimeInputs = with pkgs; [ bash coreutils ];
    text = builtins.readFile ./north-runtime-owner-guard;
  };
  northCheckoutExec = pkgs.writeShellApplication {
    name = "north-checkout-exec";
    text = builtins.readFile ./north-checkout-exec;
  };
  checkoutPreamble = name: ''
    export NORTH_CHECKOUT="''${NORTH_CHECKOUT:-$HOME/code/north/main}"
    target="$NORTH_CHECKOUT/bin/${name}"
    if [ ! -x "$target" ]; then
      echo "${name}: checkout executable missing: $target" >&2
      echo "${name}: ${name}-packaged runs the generation-pinned build" >&2
      exit 127
    fi
  '';
  checkoutHandoff = ''
    export NORTH_CHECKOUT_TARGET="$target"
    export NORTH_HOME="$NORTH_CHECKOUT"
    export NORTH_BIN="${northCheckoutExec}/bin/north-checkout-exec"
    export PATH="${northEnv}/bin:$PATH"
    exec ${northEnv}/bin/north-env "$@"
  '';
  northCheckout = pkgs.writeShellApplication {
    name = "north";
    text = ''
      ${clientEnvironment}
      ${checkoutPreamble "north"}
      ${northRuntimeOwnerGuard}/bin/north-runtime-owner-guard "$@"
      ${checkoutHandoff}
    '';
  };
  northMcpCheckout = pkgs.writeShellApplication {
    name = "north-mcp";
    text = ''
      ${clientEnvironment}
      ${checkoutPreamble "north-mcp"}
      ${checkoutHandoff}
    '';
  };
  mkPinnedCommand = name: pkgs.writeShellApplication {
    name = name;
    text = ''
      ${clientEnvironment}
      unset NORTH_CHECKOUT
      exec ${northPkg}/bin/${name} "$@"
    '';
  };
  pinnedCommandNames = [
    "north-on-spawn"
    "north-on-tooluse"
    "north-mark-delegated"
    "north-on-stop"
    "concern"
    "north-stream-sync"
    "north-pinned"
    "north-effort"
  ];
  pinnedCommands = builtins.map mkPinnedCommand pinnedCommandNames;
  mkDev = name: pkgs.writeShellApplication {
    name = "${name}-dev";
    runtimeInputs = liveInputs;
    text = ''
      ${clientEnvironment}
      checkout=''${NORTH_CHECKOUT:-$HOME/code/north/main}
      target=$checkout/bin/${name}
      if [ ! -x "$target" ]; then
        echo "${name}-dev: checkout executable missing: $target" >&2
        exit 127
      fi
      echo "${name}-dev: provenance=checkout path=$target" >&2
      export NORTH_MANAGED_CODEX_BIN='${codexPkg}/bin/codex'
      exec /run/current-system/sw/bin/north-coord-runtime exec-checkout "$target" "$@"
    '';
  };
  northDev = mkDev "north";
  northMcpDev = mkDev "north-mcp";
  northPackaged = pkgs.writeShellApplication {
    name = "north-packaged";
    text = ''
      ${clientEnvironment}
      unset NORTH_CHECKOUT
      ${northRuntimeOwnerGuard}/bin/north-runtime-owner-guard "$@"
      exec ${northPkg}/bin/north "$@"
    '';
  };
  northMcpPackaged = pkgs.writeShellApplication {
    name = "north-mcp-packaged";
    text = ''
      ${clientEnvironment}
      unset NORTH_CHECKOUT
      exec ${northPkg}/bin/north-mcp "$@"
    '';
  };
in
{
  options.myConfig.modules.north.enable = lib.mkEnableOption "checkout-executing North CLI/MCP on a generation-pinned runtime, with packaged escape hatches and packaged lifecycle hooks";
  config = lib.mkIf config.myConfig.modules.north.enable {
    environment.systemPackages = ([
      northCheckout
      northMcpCheckout
      northDev
      northMcpDev
      northPackaged
      northMcpPackaged
    ] ++ pinnedCommands);
  };
}
