{ config, lib, ... }:
let
  cfg = config.myConfig.modules.guix;
in
{
  options.myConfig.modules.guix.enable = lib.mkEnableOption "GNU Guix package manager";
  config = lib.mkIf cfg.enable { services.guix.enable = true; };
}
