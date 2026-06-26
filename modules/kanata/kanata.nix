{ config, lib, pkgs, ... }:

let
  cfg = config.myConfig.modules.kanata;
in
{
  config = lib.mkIf cfg.enable {
    hardware.uinput.enable = true;
    services.udev.extraRules = ''
      KERNEL=="uinput", MODE="0660", GROUP="uinput", OPTIONS+="static_node=uinput"

    '';
    users.groups.uinput = { };
    users.users.kanata = {
      isSystemUser = true;
      group = "kanata";
      extraGroups = [ "input" "uinput" ];
    };
    users.groups.kanata = { };
    services.kanata = {
      enable = true;
      package = pkgs.unstable.kanata;
      keyboards = lib.mkIf (cfg.devices != [ ]) {
        main = {
          devices = cfg.devices;
          port = lib.mkIf (cfg.port != null) cfg.port;
          extraDefCfg = "process-unmapped-keys yes";
          extraArgs = cfg.extraArgs;
          config = builtins.readFile cfg.configFile;
        };
      };
    };
    systemd.services.kanata-main.serviceConfig = lib.mkIf (cfg.devices != [ ]) {
      DynamicUser = lib.mkForce false;
      User = "kanata";
    };
  };
}
