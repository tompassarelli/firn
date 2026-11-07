{
  config,
  lib,
  pkgs,
  flakeRoot,
  jobRun,
  northBin,
  ...
}:

let
  cfg = config.myConfig.modules.firn-host-follow;
  homeDir = config.myConfig.modules.users.homeDir;
  username = config.myConfig.modules.users.username;
  description = "firn-host-follow: every 20 s pin the overlay to firn's main and deploy main to this machine and each remote host";
  script = name: pkgs.writeShellScript name (builtins.readFile "${flakeRoot}/dotfiles/bin/${name}");
in
{
  options.myConfig.modules.firn-host-follow = {
    enable = lib.mkEnableOption description;
    overlay = lib.mkOption {
      type = lib.types.str;
      description = "Checkout, relative to the home directory, of the overlay whose flake pins firn and builds the remote hosts.";
    };
    hosts = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "SSH names of the remote hosts that upgrade from the overlay's main through nexus-upgrade.service.";
    };
    inertPaths = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Overlay paths no host build reads; a landing that changes only these deploys nothing.";
    };
  };
  config = lib.mkIf cfg.enable {
    home-manager.users.${username} = _: {
      systemd.user = {
        services.firn-host-follow = {
          Unit = {
            Description = description;
            X-SwitchMethod = "keep-old";
          };
          Service = {
            Type = "oneshot";
            Nice = 10;
            TimeoutStartSec = "45min";
            SuccessExitStatus = "75";
            Environment = [
              "FIRN_FOLLOW_OVERLAY=${homeDir}/${cfg.overlay}"
              "\"FIRN_FOLLOW_INERT=${lib.concatStringsSep " " cfg.inertPaths}\""
              "FIRN_HOST_DEPLOY=${script "firn-host-deploy"}"
              "FIRN_HOST_PUSH=${script "firn-host-push"}"
              "PATH=/run/wrappers/bin:${northBin}:/run/current-system/sw/bin:${homeDir}/.local/share/firn/bin:${
                lib.makeBinPath [
                  pkgs.bash
                  pkgs.coreutils
                  pkgs.findutils
                  pkgs.git
                  pkgs.gnused
                  pkgs.jq
                  pkgs.nix
                  pkgs.openssh
                ]
              }"
            ];
            ExecStart = jobRun "firn-host-follow" "${script "firn-host-follow"} ${lib.escapeShellArgs cfg.hosts}";
          };
        };
        timers.firn-host-follow = {
          Unit.Description = description;
          Timer = {
            OnBootSec = "2min";
            OnUnitInactiveSec = "20s";
            AccuracySec = "5s";
          };
          Install.WantedBy = [ "timers.target" ];
        };
      };
    };
  };
}
