{ config, lib, pkgs, ... }:

((username: ((homeDir: ((loadBalancer: {
  options.myConfig.modules.codex-runtime.enable = lib.mkEnableOption "Codex provider runtime (runtime store roots, optional load balancer)";
  options.myConfig.modules.codex-runtime.loadBalancer.enable = lib.mkEnableOption "the local Codex account load balancer, for several ChatGPT accounts";
  config = lib.mkIf config.myConfig.modules.codex-runtime.enable {
    home-manager.users.${username} = ({ config, ... }: {
      systemd.user.services = {
        codex-lb = lib.mkIf loadBalancer {
          Unit = {
            Description = "Local Codex account load balancer";
            After = [ "network.target" ];
            StartLimitIntervalSec = 300;
            StartLimitBurst = 5;
          };
          Service = {
            ExecStart = "${homeDir}/.local/share/uv/tools/codex-lb/bin/codex-lb --host 127.0.0.1 --port 2455";
            Environment = [
              "SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt"
              "NIX_SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt"
              "CODEX_LB_COLLABORATION_CAPTURE_DIR=${homeDir}/.local/state/codex-collaboration-capture"
              "'CODEX_LB_COLLABORATION_CAPTURE_SESSIONS=[\"*\"]'"
              "'CODEX_LB_COLLABORATION_CAPTURE_THREADS=[\"01a07c3d-a495-78d0-a196-5921f7de2bda\"]'"
            ];
            Restart = "on-failure";
            RestartSec = 2;
            UMask = "0077";
          };
          Install = {
            WantedBy = [ "default.target" ];
          };
        };
        codex-runtime-gcroots = {
          Unit = {
            Description = "Root the Nix store dependencies of installed Codex runtimes";
          };
          Service = {
            Type = "oneshot";
            Environment = [ "PATH=${pkgs.patchelf}/bin:/run/current-system/sw/bin" ];
            ExecStart = "${homeDir}/.local/bin/codex-runtime-gcroots";
          };
          Install = {
            WantedBy = [ "default.target" ];
          };
        };
      };
    });
  };
}) config.myConfig.modules.codex-runtime.loadBalancer.enable)) config.myConfig.modules.users.homeDir)) config.myConfig.modules.users.username)
