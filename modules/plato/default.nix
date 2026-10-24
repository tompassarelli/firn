{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.myConfig.modules.plato;
  username = config.myConfig.modules.users.username;
  home = "/home/${username}";
  run = pkgs.writeShellApplication {
    name = "plato-run";
    runtimeInputs = [ pkgs.coreutils ];
    text = builtins.readFile ./plato-run.sh;
  };
  service = pkgs.writeShellApplication {
    name = "plato-service";
    runtimeInputs = [
      pkgs.tmux
      pkgs.bashInteractive
      pkgs.coreutils
    ];
    text = builtins.readFile ./plato-service.sh;
  };
in
{
  options.myConfig.modules.plato.enable =
    lib.mkEnableOption "Plato: Tom's proxy Claude session with Remote Control in tmux session plato (tmux -L plato)";
  config = lib.mkIf cfg.enable {
    users.users.${username}.linger = true;
    environment.systemPackages = [ pkgs.tmux ];
    systemd.services.plato = {
      description = "Plato: Claude Code with Remote Control in tmux session plato";
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      startLimitIntervalSec = 0;
      environment = {
        HOME = home;
        XDG_RUNTIME_DIR = "/run/user/1000";
      };
      serviceConfig = {
        User = username;
        Group = "users";
        WorkingDirectory = home;
        ExecStart = "${service}/bin/plato-service ${run}/bin/plato-run";
        Restart = "always";
        RestartSec = 10;
        OOMScoreAdjust = -500;
        CapabilityBoundingSet = "";
        NoNewPrivileges = true;
        ProtectSystem = "full";
        PrivateDevices = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        ProtectClock = true;
        LockPersonality = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        SystemCallArchitectures = "native";
        RestrictAddressFamilies = [
          "AF_UNIX"
          "AF_INET"
          "AF_INET6"
          "AF_NETLINK"
        ];
      };
    };
  };
}
