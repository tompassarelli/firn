{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.myConfig.modules.ssh-masters;
  username = config.myConfig.modules.users.username;
  hostList = lib.concatStringsSep " " cfg.hosts;
  mkMaster = host: {
    name = "ssh-master-${host}";
    value = {
      Unit = {
        Description = "ssh-master-${host}: the persistent shared ssh ControlMaster for ${host}, in its own unit so no caller's cgroup owns it";
        StartLimitIntervalSec = 0;
        X-RestartIfChanged = false;
      };
      Service = {
        Type = "simple";
        Restart = "always";
        RestartSec = "5s";
        Environment = [ "PATH=${lib.makeBinPath [ pkgs.openssh ]}" ];
        ExecStart = lib.concatStringsSep " " [
          "${pkgs.openssh}/bin/ssh"
          "-N"
          "-o ControlMaster=yes"
          "-o ControlPersist=no"
          "-o BatchMode=yes"
          "-o ConnectTimeout=20"
          "-o ServerAliveInterval=5"
          "-o ServerAliveCountMax=2"
          "-o ExitOnForwardFailure=yes"
          host
        ];
      };
      Install.WantedBy = [ "default.target" ];
    };
  };
in
{
  options.myConfig.modules.ssh-masters = {
    enable = lib.mkEnableOption "ssh-masters: one persistent ssh ControlMaster per build host in its own user unit, with every other ssh a non-master client of its socket";
    hosts = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "ssh host aliases that get a persistent master unit and the shared north-ssh ControlPath";
    };
  };
  config = lib.mkIf cfg.enable {
    programs.ssh.extraConfig = lib.mkIf (cfg.hosts != [ ]) ''
      Host ${hostList}
        ControlMaster no
        ControlPath /run/user/%i/north-ssh-%C

    '';
    home-manager.users.${username} = _: {
      systemd.user.services = builtins.listToAttrs (map mkMaster cfg.hosts);
    };
  };
}
