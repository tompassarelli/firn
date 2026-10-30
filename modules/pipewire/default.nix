{ config, lib, ... }:
let
  cfg = config.myConfig.modules.pipewire;
  audioUnits = [
    "pipewire"
    "pipewire-pulse"
    "wireplumber"
  ];
in
{
  options.myConfig.modules.pipewire.enable = lib.mkEnableOption "PipeWire audio configuration";
  config = lib.mkIf cfg.enable {
    services.pipewire = {
      alsa = {
        enable = true;
        support32Bit = true;
      };
      enable = true;
      pulse.enable = true;
    };
    systemd.user.services = lib.genAttrs audioUnits (_: {
      restartIfChanged = false;
    });
  };
}
