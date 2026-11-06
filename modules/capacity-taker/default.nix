{
  config,
  lib,
  pkgs,
  northBin,
  ...
}:

let
  cfg = config.myConfig.modules.capacity-taker;
  homeDir = config.myConfig.modules.users.homeDir;
  username = config.myConfig.modules.users.username;
  description = "capacity-taker: poll the hosts this machine reaches for a queued agent heavy run and run the oldest here under capacity admission when it has free slots beyond the interactive reserve (north#634)";
  path = "PATH=/run/wrappers/bin:/run/current-system/sw/bin:${homeDir}/.local/share/firn/bin:${northBin}:${
    lib.makeBinPath [
      pkgs.coreutils
      pkgs.gawk
      pkgs.git
      pkgs.openssh
      pkgs.util-linux
    ]
  }";
in
{
  options.myConfig.modules.capacity-taker = {
    enable = lib.mkEnableOption description;
  };
  config = lib.mkIf cfg.enable {
    home-manager.users.${username} = _: {
      systemd.user.services.capacity-taker = {
        Unit = {
          Description = description;
          OnFailure = [ "update-notify@%n.service" ];
        };
        Service = {
          Type = "simple";
          Restart = "always";
          RestartSec = "10s";
          MemoryMax = "1G";
          Environment = [ path ];
          ExecStart = "${northBin}/north capacity offload take";
        };
        Install.WantedBy = [ "default.target" ];
      };
    };
  };
}
