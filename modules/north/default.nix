{ config, lib, pkgs, inputs, ... }:

let
  northPkg = inputs.north.packages."${pkgs.stdenv.hostPlatform.system}".default;
  liveInputs = with pkgs; [ bash coreutils git babashka bun jq ];
  northLive = pkgs.writeShellApplication {
    name = "north";
    runtimeInputs = liveInputs;
    text = ''
      checkout=''${NORTH_CHECKOUT:-$HOME/code/north}
      target=$checkout/bin/north
      if [ ! -x "$target" ]; then
        echo "north: live checkout executable missing: $target" >&2
        echo "north: restore that checkout or use north-packaged for the pinned closure" >&2
        exit 127
      fi
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
      exec /run/current-system/sw/bin/north-coord-runtime exec-checkout "$target" "$@"
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
