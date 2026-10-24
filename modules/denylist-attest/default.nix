{
  config,
  lib,
  pkgs,
  northBin,
  ...
}:

let
  cfg = config.myConfig.modules.denylist-attest;
  homeDir = config.myConfig.modules.users.homeDir;
  username = config.myConfig.modules.users.username;
  path = "PATH=/run/wrappers/bin:/run/current-system/sw/bin:${northBin}:${
    lib.makeBinPath [
      pkgs.gh
      pkgs.git
      pkgs.gitleaks
      pkgs.coreutils
    ]
  }";
in
{
  options.myConfig.modules.denylist-attest.enable =
    lib.mkEnableOption "denylist-attest: every five minutes, scan new claude/ branch tips of the public Autoland repositories against the private deny-list and post their denylist commit status; enable it on exactly one host, one with south and gh signed in";
  config = lib.mkIf cfg.enable {
    home-manager.users.${username} = _: {
      systemd.user = {
        services.denylist-attest = {
          Unit.Description = "Attest claude/ branch tips against the private deny-list";
          Service = {
            Type = "oneshot";
            Environment = [ path ];
            ExecStart = "${northBin}/north denylist attest --south ${homeDir}/code/south --repo tompassarelli/smashcraft --repo tompassarelli/wisp";
          };
        };
        timers.denylist-attest = {
          Unit.Description = "Attest claude/ branch tips every five minutes";
          Timer = {
            OnCalendar = "*-*-* *:00/5:00";
            Persistent = true;
          };
          Install.WantedBy = [ "timers.target" ];
        };
      };
    };
  };
}
