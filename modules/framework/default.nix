{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.myConfig.modules.framework;
  username = config.myConfig.modules.users.username;
  sleepDrain = pkgs.writeShellApplication {
    name = "sleep-drain";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.util-linux
      pkgs.systemd
    ];
    runtimeEnv.DRAIN_USER = username;
    text = builtins.readFile ./sleep-drain.sh;
  };
in
{
  options.myConfig.modules.framework.enable = lib.mkEnableOption "Framework Computer specific tools";
  config = lib.mkIf cfg.enable {
    boot.extraModprobeConfig = ''
      options mt7925_common disable_clc=1
      options mt7925e disable_aspm=1

    '';
    services.udev.extraRules = ''
      ACTION=="add", SUBSYSTEM=="drm", KERNEL=="card[0-9]*", DRIVERS=="amdgpu", ATTR{device/power_dpm_force_performance_level}="high"
    '';
    networking.networkmanager.dispatcherScripts =
      map
        (type: {
          inherit type;
          source = "${sleepDrain}/bin/sleep-drain";
        })
        [
          "pre-down"
          "basic"
        ];
    systemd.sleep.settings.Sleep.HibernateDelaySec = "30min";
    services.logind.settings.Login = {
      HandleLidSwitch = "suspend-then-hibernate";
      HandleLidSwitchExternalPower = "ignore";
    };
  };
}
