{ config, lib, ... }:
let
  cfg = config.myConfig.modules.input;
in
{
  config = lib.mkIf cfg.enable { services.libinput.enable = true; };
  options.myConfig.modules.input.enable = lib.mkEnableOption "touchpad support (libinput)";
}
