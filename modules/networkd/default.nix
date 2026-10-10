{ config, lib, pkgs, ... }:

((cfg: ((static: {
  options.myConfig.modules.networkd.enable = lib.mkEnableOption "systemd-networkd with DHCP on every wired interface";
  options.myConfig.modules.networkd.staticSopsFile = lib.mkOption {
    type = lib.types.nullOr lib.types.path;
    default = null;
    description = "sops file with nexus-public-mac, nexus-public-address (CIDR) and nexus-public-gateway; when set, that interface is configured statically instead of DHCP (DigitalOcean serves no DHCP)";
  };
  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      networking.useNetworkd = true;
      networking.useDHCP = false;
      systemd.network.enable = true;
    }
    (lib.mkIf (!static) {
      systemd.network.networks."10-ether" = {
        matchConfig.Type = "ether";
        networkConfig.DHCP = "yes";
        linkConfig.RequiredForOnline = "routable";
      };
    })
    (lib.mkIf static {
      sops.secrets.nexus-public-mac.sopsFile = cfg.staticSopsFile;
      sops.secrets.nexus-public-address.sopsFile = cfg.staticSopsFile;
      sops.secrets.nexus-public-gateway.sopsFile = cfg.staticSopsFile;
      networking.nameservers = [ "1.1.1.1" "9.9.9.9" ];
      sops.templates."nexus-public-network" = {
        path = "/etc/systemd/network/10-public.network";
        mode = "0444";
        restartUnits = [ "systemd-networkd.service" ];
        content = ''
          [Match]
          MACAddress=${config.sops.placeholder.nexus-public-mac}

          [Network]
          Address=${config.sops.placeholder.nexus-public-address}
          Gateway=${config.sops.placeholder.nexus-public-gateway}
          DNS=1.1.1.1
          DNS=9.9.9.9

          [Link]
          RequiredForOnline=routable

        '';
      };
    })
  ]);
}) (cfg.staticSopsFile != null))) config.myConfig.modules.networkd)
