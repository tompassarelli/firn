{ config, lib, pkgs, ... }:

((username: {
  tags = [ vpn ];
  options.myConfig.modules.wireguard.enable = lib.mkEnableOption "WireGuard VPN support";
  config = lib.mkIf config.myConfig.modules.wireguard.enable {
    security.sudo.extraRules = [
      {
        users = [ username ];
        commands = [
          {
            command = "${pkgs.wireguard-tools}/bin/wg";
            options = [ "NOPASSWD" ];
          }
        ];
      }
    ];
    networking.firewall.checkReversePath = "loose";
    services.resolved.enable = true;
    systemd.services.wireguard-watchdog = {
      description = "WireGuard connection watchdog";
      after = [ "network.target" ];
      serviceConfig = {
        Type = "simple";
        Restart = "always";
        RestartSec = 5;
        ExecStart = ((watchdog: "${watchdog}") (pkgs.writeShellScript "wg-watchdog" ''
            export PATH="${lib.makeBinPath [
                        pkgs.wireguard-tools
                        pkgs.iputils
                        pkgs.gawk
                        pkgs.coreutils
                        pkgs.systemd
                      ]}:$PATH"

            MISS_COUNT=0
            MISS_THRESHOLD=5

            while true; do
              IFACE=wg0

              if ! wg show "$IFACE" >/dev/null 2>&1; then
                sleep 5
                continue
              fi

              # Get gateway IP from the first peer's allowed IP.
              GATEWAY=$(wg show "$IFACE" allowed-ips 2>/dev/null | awk 'NR == 1 { split($2, ips, ","); sub(/\/.*$/, "", ips[1]); print ips[1]; exit }')
              if [ -z "$GATEWAY" ]; then
                sleep 5
                continue
              fi

              if ! ping -c 1 -W 1 -I "$IFACE" "$GATEWAY" >/dev/null 2>&1; then
                MISS_COUNT=$((MISS_COUNT + 1))
                echo "$(date): Ping miss $MISS_COUNT/$MISS_THRESHOLD on $IFACE"

                if [ $MISS_COUNT -ge $MISS_THRESHOLD ]; then
                  echo "$(date): Connection dead on $IFACE, full restart"

                  systemctl restart wireguard-wg0.service
                  echo "$(date): Interface $IFACE restarted"

                  MISS_COUNT=0
                  sleep 3
                fi
              else
                MISS_COUNT=0
              fi

              sleep 1
            done

          ''));
      };
      wantedBy = [ "multi-user.target" ];
    };
    environment.systemPackages = with pkgs; [ wireguard-tools ];
  };
}) config.myConfig.modules.users.username)
