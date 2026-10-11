{ config, lib, pkgs, ... }:

((cfg: ((address: ((port: ((upstream: ((dataDir: ((wgInterface: ((domain: ((acmeEnv: {
  options.myConfig.modules.nexus-matrix.enable = lib.mkEnableOption "continuwuity Matrix homeserver for agent chat on wg-nexus: no federation, closed registration";
  options.myConfig.modules.nexus-matrix.serverName = lib.mkOption {
    type = lib.types.str;
    description = "Matrix server_name, the suffix of user and room ids; with tls it is also the https host name";
  };
  options.myConfig.modules.nexus-matrix.tls.enable = lib.mkEnableOption "https for the server name on wg-nexus port 443 through nginx with an ACME DNS-01 Cloudflare certificate";
  options.myConfig.modules.nexus-matrix.tls.credentialsSopsFile = lib.mkOption {
    type = lib.types.path;
    description = "sops file holding cloudflare-dns-api-token, a Cloudflare token with DNS edit on the server name's zone";
  };
  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      services.matrix-continuwuity = {
        enable = true;
        package = pkgs.matrix-continuwuity_latest;
        settings.global = {
          server_name = cfg.serverName;
          address = [ address ];
          port = [ port ];
          allow_registration = false;
          allow_federation = false;
          trusted_servers = [ ];
          allow_announcements_check = false;
        };
      };
      systemd.services.continuwuity.serviceConfig = {
        DynamicUser = lib.mkForce false;
        StateDirectoryMode = lib.mkForce "0750";
      };
      networking.firewall.interfaces.${wgInterface}.allowedTCPPorts = lib.concatLists [ [ port ] (lib.optional cfg.tls.enable 443) ];
      myConfig.modules.nexus-backup.paths = lib.mkOptionDefault [ dataDir ];
    }
    (lib.mkIf config.myConfig.modules.nexus-backup.enable {
      systemd.services.state-backup.serviceConfig.SupplementaryGroups = [ "continuwuity" ];
    })
    (lib.mkIf cfg.tls.enable {
      sops.secrets.cloudflare-dns-api-token.sopsFile = cfg.tls.credentialsSopsFile;
      sops.templates."acme-cloudflare.env".content = ''
        CLOUDFLARE_DNS_API_TOKEN=${config.sops.placeholder.cloudflare-dns-api-token}

      '';
      security.acme = {
        acceptTerms = true;
        certs = {
          ${domain} = {
            dnsProvider = "cloudflare";
            environmentFile = acmeEnv.path;
            group = "nginx";
          };
        };
      };
      services.matrix-continuwuity.settings.global.well_known.client = "https://${domain}";
      services.nginx = {
        enable = true;
        recommendedProxySettings = true;
        recommendedTlsSettings = true;
        virtualHosts = {
          ${domain} = {
            listen = [
              {
                addr = address;
                port = 443;
                ssl = true;
              }
            ];
            onlySSL = true;
            useACMEHost = domain;
            locations = {
              "/" = {
                proxyPass = upstream;
                extraConfig = "client_max_body_size 20M;";
              };
            };
          };
        };
      };
    })
  ]);
}) (builtins.getAttr "acme-cloudflare.env" config.sops.templates))) cfg.serverName)) "wg-nexus")) "/var/lib/continuwuity")) "http://${address}:${builtins.toString port}")) 6167)) "10.77.0.1")) config.myConfig.modules.nexus-matrix)
