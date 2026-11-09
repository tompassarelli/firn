{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.opencode;
in
{
  options.myConfig.modules.opencode.enable =
    lib.mkEnableOption "opencode terminal coding agent (MIT, nixpkgs-unstable)";
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.unstable.opencode ]; };
}
