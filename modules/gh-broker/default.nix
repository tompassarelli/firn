{
  config,
  lib,
  pkgs,
  northBin,
  ...
}:

let
  cfg = config.myConfig.modules.gh-broker;
  username = config.myConfig.modules.users.username;
  description = "north gh-broker: every gh call on this host goes through one broker that shares, revalidates and paces GitHub reads and logs each call by session or unit";
in
{
  options.myConfig.modules.gh-broker = {
    enable = lib.mkEnableOption description;
  };
  config = lib.mkIf cfg.enable {
    home-manager.users.${username} = _: {
      systemd.user.services.north-gh-broker = {
        Unit = {
          Description = description;
          StartLimitIntervalSec = 0;
        };
        Service = {
          Type = "notify";
          NotifyAccess = "main";
          Slice = "control.slice";
          Restart = "always";
          RestartSec = "2s";
          Environment = [
            "PATH=${northBin}:/run/wrappers/bin:/run/current-system/sw/bin:${
              lib.makeBinPath [
                pkgs.curl
                pkgs.coreutils
              ]
            }"
          ];
          ExecStartPre = "${northBin}/north gh-broker release";
          ExecStart = "${northBin}/north gh-broker serve --resident";
          ExecStopPost = "${northBin}/north gh-broker release";
        };
        Install.WantedBy = [ "default.target" ];
      };
    };
  };
}
