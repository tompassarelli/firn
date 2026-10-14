{ config, lib, ... }:
let
  cfg = config.myConfig.modules.input;
in
{
  options.myConfig.modules.input.enable = lib.mkEnableOption "touchpad support (libinput)";
  config = lib.mkIf cfg.enable { services.libinput.enable = true; };
}
