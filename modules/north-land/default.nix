{
  config,
  lib,
  pkgs,
  northBin,
  ...
}:

let
  cfg = config.myConfig.modules.north-land;
  homeDir = config.myConfig.modules.users.homeDir;
  username = config.myConfig.modules.users.username;
  description = "north-land: the lander, which checks the queued lane tickets as one candidate and lands them on north main";
in
{
  options.myConfig.modules.north-land.enable = lib.mkEnableOption description;
  config = lib.mkIf cfg.enable {
    home-manager.users.${username} = _: {
      systemd.user.services.north-land = {
        Unit.Description = description;
        Service = {
          Type = "simple";
          Restart = "always";
          RestartSec = "5s";
          Nice = 5;
          Environment = [
            "PATH=/run/wrappers/bin:/run/current-system/sw/bin:${homeDir}/.local/bin:${northBin}:${homeDir}/.local/share/firn/bin:${
              lib.makeBinPath [
                pkgs.bash
                pkgs.bun
                pkgs.coreutils
                pkgs.git
                pkgs.gnutar
                pkgs.nix
                pkgs.openssh
                pkgs.rsync
                pkgs.systemd
                pkgs.util-linux
              ]
            }"
          ];
          ExecStart = "${northBin}/north land serve --repo ${homeDir}/code/north/main";
        };
        Install.WantedBy = [ "default.target" ];
      };
    };
  };
}
