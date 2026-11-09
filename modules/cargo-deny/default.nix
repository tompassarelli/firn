{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.cargo-deny;
in
{
  options.myConfig.modules.cargo-deny.enable =
    lib.mkEnableOption "cargo-deny, which north's dependency advisory gate runs at enqueue and in the lander";
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.cargo-deny ]; };
}
