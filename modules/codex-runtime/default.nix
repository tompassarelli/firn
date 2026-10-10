{ config, lib, pkgs, ... }:

((username: ((homeDir: {
  options.myConfig.modules.codex-runtime.enable = lib.mkEnableOption "Codex provider runtime (runtime store roots)";
  config = lib.mkIf config.myConfig.modules.codex-runtime.enable {
    home-manager.users.${username} = ({ config, ... }: {
      systemd.user.services.codex-runtime-gcroots = {
        Unit = {
          Description = "Root the Nix store dependencies of installed Codex runtimes";
        };
        Service = {
          Type = "oneshot";
          Environment = [ "PATH=${pkgs.patchelf}/bin:/run/current-system/sw/bin" ];
          ExecStart = "${homeDir}/.local/share/north/bin/codex-runtime-gcroots";
        };
        Install = {
          WantedBy = [ "default.target" ];
        };
      };
    });
  };
}) config.myConfig.modules.users.homeDir)) config.myConfig.modules.users.username)
