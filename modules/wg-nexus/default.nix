{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.myConfig.modules.wg-nexus;
  hubPublicKey = "Dvmfg8eA5NBuadrl3CoEW1ZstHMxD7CT9r3l6HlMQx4=";
  laptopPublicKey = "ynrELQcn+uM+tllUWa/o5IpPbjHKPPJAStI3gq23EhI=";
  template = builtins.getAttr "wg-nexus.conf" config.sops.templates;
  peerNames = lib.concatStringsSep " " (
    lib.concatLists [
      [ "laptop:${laptopPublicKey}" ]
      (lib.optional (cfg.phonePublicKey != null) "phone:${cfg.phonePublicKey}")
      (lib.optional (cfg.gex45PublicKey != null) "gex45:${cfg.gex45PublicKey}")
    ]
  );
  peersHelper = pkgs.writeShellApplication {
    name = "nexus-peers";
    runtimeInputs = [
      pkgs.wireguard-tools
      pkgs.jq
      pkgs.coreutils
    ];
    runtimeEnv.PEERS = peerNames;
    text = ''
      out=/run/nexus/peers.json
      prev=$(cat "$out" 2>/dev/null || echo '{}')
      wg show wg-nexus latest-handshakes | jq -R -n --argjson prev "$prev" --argjson now "$(date +%s)" --arg names "$PEERS" '
        ($names | split(" ") | map(split(":") | {key: .[1], value: .[0]}) | from_entries) as $map
        | [inputs | split("\t") | select($map[.[0]]) | {name: $map[.[0]], hs: (.[1] | tonumber)}]
        | {updated: $now, peers: (map(. as $p | (($p.hs > 0) and ($now - $p.hs < 300)) as $on
            | {key: $p.name, value: {handshake: (if $p.hs > 0 then $p.hs else null end), online: $on,
               online_since: (if $on then ($prev.peers[$p.name].online_since // $p.hs) else null end)}}) | from_entries)}' >"$out.tmp"
      mv "$out.tmp" "$out"
    '';
  };
in
{
  options.myConfig.modules.wg-nexus = {
    enable = lib.mkEnableOption "private WireGuard network wg-nexus (10.77.0.0/24): nexus hub .1, laptop .2, phone .3, gex45 .4";
    role = lib.mkOption {
      type = lib.types.enum [
        "hub"
        "client"
      ];
      description = "hub listens on UDP 51820 with the laptop and phone as peers; client is the laptop dialing the hub";
    };
    sopsFile = lib.mkOption {
      type = lib.types.path;
      description = "hub: sops file holding the wireguard-nexus private key";
    };
    hostPublicKeyFile = lib.mkOption {
      type = lib.types.path;
      description = "client: file holding the hub's SSH host ed25519 public key, pinned as known host nexus";
    };
    phonePublicKey = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Public key of the phone peer (10.77.0.3); the hub omits the peer while null";
    };
    gex45PublicKey = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Public key of the gex45 peer (10.77.0.4); the hub omits the peer while null";
    };
    address = lib.mkOption {
      type = lib.types.str;
      default = "10.77.0.2";
      description = "client: this host's wg-nexus address";
    };
    keySecret = lib.mkOption {
      type = lib.types.str;
      default = "wireguard-nexus-laptop";
      description = "client: sops secret name holding this host's wg-nexus private key";
    };
    acceptInbound = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "client: accept new inbound connections on wg-nexus (subject to the host firewall) instead of dropping them";
    };
  };
  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      { environment.systemPackages = [ pkgs.wireguard-tools ]; }
      (lib.mkIf (cfg.role == "hub") {
        sops.secrets.wireguard-nexus.sopsFile = cfg.sopsFile;
        systemd = {
          services.nexus-peers = {
            description = "Write the wg-nexus peers' latest handshakes and online-since times to /run/nexus/peers.json";
            after = [ "wireguard-wg-nexus.service" ];
            serviceConfig = {
              Type = "oneshot";
              RuntimeDirectory = "nexus";
              RuntimeDirectoryMode = "0755";
              RuntimeDirectoryPreserve = "yes";
              ExecStart = "${peersHelper}/bin/nexus-peers";
            };
          };
          timers.nexus-peers = {
            wantedBy = [ "timers.target" ];
            timerConfig = {
              OnBootSec = "1min";
              OnUnitActiveSec = "1min";
              AccuracySec = "5s";
            };
          };
        };
        networking.wireguard.interfaces.wg-nexus = {
          ips = [ "10.77.0.1/24" ];
          listenPort = 51820;
          privateKeyFile = config.sops.secrets.wireguard-nexus.path;
          peers = lib.concatLists [
            [
              {
                publicKey = laptopPublicKey;
                allowedIPs = [ "10.77.0.2/32" ];
              }
            ]
            (lib.optional (cfg.phonePublicKey != null) {
              publicKey = cfg.phonePublicKey;
              allowedIPs = [ "10.77.0.3/32" ];
            })
            (lib.optional (cfg.gex45PublicKey != null) {
              publicKey = cfg.gex45PublicKey;
              allowedIPs = [ "10.77.0.4/32" ];
            })
          ];
        };
      })
      (lib.mkIf (cfg.role == "client") {
        sops = {
          secrets = {
            ${cfg.keySecret} = { };
            nexus-endpoint = { };
          };
          templates."wg-nexus.conf" = {
            restartUnits = [ "wg-quick-wg-nexus.service" ];
            content = ''
              [Interface]
              PrivateKey = ${builtins.getAttr cfg.keySecret config.sops.placeholder}
              Address = ${cfg.address}/24

              [Peer]
              PublicKey = ${hubPublicKey}
              Endpoint = ${config.sops.placeholder.nexus-endpoint}
              AllowedIPs = 10.77.0.0/24
              PersistentKeepalive = 25

            '';
          };
        };
        networking = {
          wg-quick.interfaces.wg-nexus.configFile = template.path;
          firewall.extraCommands = lib.mkIf (
            !cfg.acceptInbound
          ) "ip46tables -I nixos-fw 1 -i wg-nexus -m conntrack ! --ctstate ESTABLISHED,RELATED -j DROP";
        };
        programs.ssh = {
          extraConfig = ''
            Host nexus
              HostName 10.77.0.1
              User tom
              IdentityFile ~/.ssh/nexus
              IdentitiesOnly yes

          '';
          knownHosts.nexus = {
            hostNames = [
              "nexus"
              "10.77.0.1"
            ];
            publicKeyFile = cfg.hostPublicKeyFile;
          };
        };
      })
    ]
  );
}
