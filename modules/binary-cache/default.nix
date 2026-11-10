{ config, lib, ... }:

let
  cfg = config.myConfig.modules.binary-cache;
in
{
  options.myConfig.modules.binary-cache = {
    serve = {
      enable = lib.mkEnableOption "a signed Nix binary cache (Harmonia) that serves this host's store, so every other host substitutes what this build host built instead of building it";
      address = lib.mkOption {
        type = lib.types.str;
        description = "address the cache listens on, a private-network address of this host";
      };
      port = lib.mkOption {
        type = lib.types.port;
        default = 5000;
        description = "TCP port the cache listens on";
      };
      interface = lib.mkOption {
        type = lib.types.str;
        description = "network interface whose firewall opens the port, the private link the address belongs to";
      };
      signingKeyFile = lib.mkOption {
        type = lib.types.str;
        description = "runtime path of the Nix secret signing key (a sops secret); the cache signs every path it serves with it and this host's nix daemon signs every path it builds with it";
      };
    };
    substituters = lib.mkOption {
      type = lib.types.listOf (
        lib.types.submodule {
          options = {
            url = lib.mkOption {
              type = lib.types.str;
              description = "URL of a cache another host serves with `serve.enable`, such as http://10.77.0.6:5000";
            };
            publicKey = lib.mkOption {
              type = lib.types.str;
              description = "public key of that cache's signing key, the only key its paths are trusted by";
            };
          };
        }
      );
      default = [ ];
      description = "build-host caches this host substitutes from ahead of the public caches";
    };
  };
  config = lib.mkMerge [
    (lib.mkIf cfg.serve.enable {
      services.harmonia.cache = {
        enable = true;
        signKeyPaths = [ cfg.serve.signingKeyFile ];
        settings.bind = "${cfg.serve.address}:${toString cfg.serve.port}";
      };
      systemd.sockets.harmonia.socketConfig.FreeBind = true;
      nix.settings.secret-key-files = [ cfg.serve.signingKeyFile ];
      networking.firewall.interfaces.${cfg.serve.interface}.allowedTCPPorts = [ cfg.serve.port ];
    })
    (lib.mkIf (cfg.substituters != [ ]) {
      nix.settings = {
        extra-substituters = map (s: "${s.url}?priority=30") cfg.substituters;
        extra-trusted-public-keys = map (s: s.publicKey) cfg.substituters;
      };
    })
  ];
}
