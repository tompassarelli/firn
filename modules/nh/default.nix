{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.nh;
in
{
  options.myConfig.modules.nh.enable =
    lib.mkEnableOption "Nix helper (nicer nixos-rebuild output, generation diff, search, clean)";
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.nh ]; };
}
