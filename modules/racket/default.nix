{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.racket;
in
{
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.unstable.racket ]; };
  options.myConfig.modules.racket.enable = lib.mkEnableOption "Racket programming language";
}
