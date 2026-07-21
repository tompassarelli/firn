{ config, lib, pkgs, inputs, ... }:

let
  northPkg = inputs.north.packages."${pkgs.stdenv.hostPlatform.system}".default;
  codexPkg = inputs.north.packages."${pkgs.stdenv.hostPlatform.system}".codex;
  liveInputs = with pkgs; [ bash coreutils git babashka bun jq ];
  northRuntimeOwnerGuard = pkgs.writeShellApplication {
    name = "north-runtime-owner-guard";
    runtimeInputs = with pkgs; [ bash coreutils ];
    text = builtins.readFile ./north-runtime-owner-guard;
  };
  northLive = pkgs.writeShellApplication {
    name = "north";
    runtimeInputs = liveInputs;
    text = ''
      checkout=''${NORTH_CHECKOUT:-$HOME/code/north}
      target=$checkout/bin/north
      ${northRuntimeOwnerGuard}/bin/north-runtime-owner-guard "$@"
      if [ ! -x "$target" ]; then
        echo "north: live checkout executable missing: $target" >&2
        echo "north: restore that checkout or use north-packaged for the pinned closure" >&2
        exit 127
      fi
      export NORTH_MANAGED_CODEX_BIN='${codexPkg}/bin/codex'
      exec /run/current-system/sw/bin/north-coord-runtime exec-checkout "$target" "$@"
    '';
  };
  northMcpLive = pkgs.writeShellApplication {
    name = "north-mcp";
    runtimeInputs = liveInputs;
    text = ''
      checkout=''${NORTH_CHECKOUT:-$HOME/code/north}
      target=$checkout/bin/north-mcp
      if [ ! -x "$target" ]; then
        echo "north-mcp: live checkout executable missing: $target" >&2
        echo "north-mcp: restore that checkout or use north-mcp-packaged for the pinned closure" >&2
        exit 127
      fi
      export NORTH_MANAGED_CODEX_BIN='${codexPkg}/bin/codex'
      exec /run/current-system/sw/bin/north-coord-runtime exec-checkout "$target" "$@"
    '';
  };
  northPackaged = pkgs.writeShellApplication {
    name = "north-packaged";
    text = ''
      ${northRuntimeOwnerGuard}/bin/north-runtime-owner-guard "$@"
      exec ${northPkg}/bin/north "$@"
    '';
  };
  northMcpPackaged = pkgs.writeShellApplication {
    name = "north-mcp-packaged";
    text = ''
      exec ${northPkg}/bin/north-mcp "$@"
    '';
  };
in
{
  options.myConfig.modules.north.enable = lib.mkEnableOption "checkout-first North CLI/MCP with explicit packaged smoke commands";
  config = lib.mkIf config.myConfig.modules.north.enable {
    environment.systemPackages = [ northLive northMcpLive northPackaged northMcpPackaged ];
  };
}
