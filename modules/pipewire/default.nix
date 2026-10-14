{ config, lib, ... }:
let
  cfg = config.myConfig.modules.pipewire;
in
{
  config = lib.mkIf cfg.enable {
    services.pipewire = {
      alsa = {
        enable = true;
        support32Bit = true;
      };
      enable = true;
      pulse.enable = true;
    };
  };
  options.myConfig.modules.pipewire.enable = lib.mkEnableOption "PipeWire audio configuration";
}
