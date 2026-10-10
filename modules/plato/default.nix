{ config, lib, pkgs, ... }:

((username: ((home: ((run: ((service: {
  options.myConfig.modules.plato.enable = lib.mkEnableOption "Plato: Tom's proxy Claude session with Remote Control in tmux session plato (tmux -L plato)";
  config = lib.mkIf config.myConfig.modules.plato.enable {
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
      };
    };
  };
}) (pkgs.writeShellApplication {
    name = "plato-service";
    runtimeInputs = [ pkgs.tmux pkgs.bashInteractive pkgs.coreutils ];
    text = builtins.readFile ./plato-service.sh;
  }))) (pkgs.writeShellApplication {
    name = "plato-run";
    runtimeInputs = [ pkgs.coreutils ];
    text = builtins.readFile ./plato-run.sh;
  }))) "/home/${username}")) config.myConfig.modules.users.username)
