{ config, lib, pkgs, inputs, ... }:

let
  northPkg = inputs.north.packages."${pkgs.stdenv.hostPlatform.system}".default;
  liveInputs = with pkgs; [ bash coreutils git babashka bun jq ];
  northLive = pkgs.writeShellApplication {
    name = "north";
    runtimeInputs = liveInputs;
    text = ''
      checkout=''${NORTH_CHECKOUT:-$HOME/code/north-routing-robustness-landing}
      runtimeRoot=''${NORTH_COORD_RUNTIME_STATE:-$HOME/.local/state/north/fram-runtime}/current
      if [ ! -L "$runtimeRoot" ] || [ ! -x "$runtimeRoot/bin/fram-daemon" ]; then
        echo "north: selected Fram checkout runtime is missing: $runtimeRoot" >&2
        echo "north: run north-coord-runtime promote, then restart north-coord.service" >&2
        exit 127
      fi
      if ! git -C "$runtimeRoot" rev-parse --show-toplevel >/dev/null 2>&1; then
        echo "north: selected Fram runtime is package mode; use north-packaged or promote a checkout" >&2
        exit 2
      fi
      export NORTH_FRAM_RUNTIME=checkout
      export FRAM_HOME=$runtimeRoot
      export FRAM_BIN=$runtimeRoot/bin
      target=$checkout/bin/north
      if [ ! -x "$target" ]; then
        echo "north: live checkout executable missing: $target" >&2
        echo "north: restore that checkout or use north-packaged for the pinned closure" >&2
        exit 127
      fi
      exec "$target" "$@"
    '';
  };
  northMcpLive = pkgs.writeShellApplication {
    name = "north-mcp";
    runtimeInputs = liveInputs;
    text = ''
      checkout=''${NORTH_CHECKOUT:-$HOME/code/north-routing-robustness-landing}
      runtimeRoot=''${NORTH_COORD_RUNTIME_STATE:-$HOME/.local/state/north/fram-runtime}/current
      if [ ! -L "$runtimeRoot" ] || [ ! -x "$runtimeRoot/bin/fram-daemon" ]; then
        echo "north-mcp: selected Fram checkout runtime is missing: $runtimeRoot" >&2
        echo "north-mcp: run north-coord-runtime promote, then restart north-coord.service" >&2
        exit 127
      fi
      if ! git -C "$runtimeRoot" rev-parse --show-toplevel >/dev/null 2>&1; then
        echo "north-mcp: selected Fram runtime is package mode; use north-mcp-packaged or promote a checkout" >&2
        exit 2
      fi
      export NORTH_FRAM_RUNTIME=checkout
      export FRAM_HOME=$runtimeRoot
      export FRAM_BIN=$runtimeRoot/bin
      target=$checkout/bin/north-mcp
      if [ ! -x "$target" ]; then
        echo "north-mcp: live checkout executable missing: $target" >&2
        echo "north-mcp: restore that checkout or use north-mcp-packaged for the pinned closure" >&2
        exit 127
      fi
      exec "$target" "$@"
    '';
  };
  northPackaged = pkgs.writeShellApplication {
    name = "north-packaged";
    text = ''
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
