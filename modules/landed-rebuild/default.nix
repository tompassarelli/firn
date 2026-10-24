{
  config,
  lib,
  pkgs,
  flakeRoot,
  ...
}:

let
  username = config.myConfig.modules.users.username;
  homeDir = config.myConfig.modules.users.homeDir;
  cfg = config.myConfig.modules.landed-rebuild;
  environmentSwitch = pkgs.writeShellScript "firn-environment-switch" (
    builtins.readFile "${flakeRoot}/dotfiles/bin/firn-environment-switch"
  );
in
{
  options.myConfig.modules.landed-rebuild = {
    enable = lib.mkEnableOption "Activate only the freshly fetched landed main commit from sandboxed agents";
  };
  config = lib.mkIf cfg.enable {
    systemd = {
      sockets.firn-landed-rebuild = {
        description = "Firn landed-commit rebuild requests";
        wantedBy = [ "sockets.target" ];
        socketConfig = {
          ListenStream = "/run/firn-landed-rebuild.sock";
          SocketMode = "0600";
          SocketUser = username;
        };
      };
      services.firn-landed-rebuild = {
        description = "Activate the current Firn main commit through firn rebuild";
        path = [
          pkgs.git
          pkgs.util-linux
          pkgs.coreutils
        ];
        restartIfChanged = false;
        environment.PATH = lib.mkForce "/run/wrappers/bin:/run/current-system/sw/bin:${
          lib.makeBinPath [
            pkgs.git
            pkgs.util-linux
            pkgs.coreutils
          ]
        }";
        serviceConfig = {
          ExecStart = "${pkgs.python3}/bin/python3 ${./landed-rebuild.py} serve ${username} ${homeDir} ${pkgs.bun}/bin/bun ${./runtime.mjs} ${environmentSwitch}";
          StateDirectory = "firn-landed-rebuild";
          StateDirectoryMode = "0700";
          UMask = "0077";
          KillMode = "process";
          Restart = "on-failure";
        };
      };
    };
  };
}
