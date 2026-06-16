{ config, lib, pkgs, ... }:

let
  lodestar = pkgs.writeShellScriptBin "lodestar" ''
    #!/usr/bin/env bash
    # `lodestar` on PATH = the life-app wrapper (aims the domain-neutral Fram
    # engine at your private claim data). The wrapper in ~/code/lodestar/bin is
    # the source of truth; this only puts it on PATH declaratively.
    # Engine: ~/code/fram · data: ~/code/lodestar-data (XDG ~/.local/state/lodestar).
    exec "$HOME/code/lodestar/bin/lodestar" "$@"
  '';
in
{
  options.myConfig.modules.lodestar.enable = lib.mkEnableOption "Lodestar (life app) CLI on PATH";
  config = lib.mkIf config.myConfig.modules.lodestar.enable {
    environment.systemPackages = [ lodestar ];
  };
}
