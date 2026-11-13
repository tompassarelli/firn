{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.sccache;
  username = config.myConfig.modules.users.username;
  sccache = "${pkgs.sccache}/bin/sccache";
  relayPort = 16380;
  relaySocket = "/run/sccache-remote/http.sock";
  cacheRoot = "/var/lib/sccache-cache";
  remoteLevel = lib.optionalString (cfg.remote != null) ''
    if [ -n "''${SCCACHE_SERVER_UDS:-}" ]; then
      [ -S "$SCCACHE_SERVER_UDS" ] && exec ${sccache} "$@"
    elif (exec 3<>/dev/tcp/127.0.0.1/"''${SCCACHE_SERVER_PORT:-4226}") 2>/dev/null; then
      exec ${sccache} "$@"
    fi
    relay() { (exec 3<>/dev/tcp/127.0.0.1/${toString relayPort}) 2>/dev/null; }
    if ! relay && [ -S ${relaySocket} ]; then
      ${pkgs.util-linux}/bin/setsid ${lib.getExe pkgs.socat} TCP-LISTEN:${toString relayPort},bind=127.0.0.1,fork,reuseaddr UNIX-CONNECT:${relaySocket} </dev/null >/dev/null 2>&1 &
      for _ in 1 2 3 4 5 6 7 8 9 10; do relay && break; ${pkgs.coreutils}/bin/sleep 0.05; done
    fi
    if relay; then
      export SCCACHE_MULTILEVEL_CHAIN=disk,webdav SCCACHE_WEBDAV_ENDPOINT=http://127.0.0.1:${toString relayPort}
    fi
  '';
  serverUp = ''
    server_up() {
      if [ -n "''${SCCACHE_SERVER_UDS:-}" ]; then
        [ -S "$SCCACHE_SERVER_UDS" ]
      else
        (exec 3<>/dev/tcp/127.0.0.1/"''${SCCACHE_SERVER_PORT:-4226}") 2>/dev/null
      fi
    }
  '';
  startOrBypass = ''
    if ! server_up && ! startup_error=$(${sccache} --start-server 2>&1 >/dev/null) && ! server_up; then
      printf 'sccache: cache unusable (%s), compiling without it\n' "$(printf %s "$startup_error" | ${pkgs.gnused}/bin/sed -n 's/.*startup failed: //p;T;q')" >&2
      exec "$@"
    fi
  '';
  wrapper = pkgs.writeShellScript "sccache-lane" ''
    ${serverUp}
    out=$PWD prev=
    for arg in "$@"; do
      [ "$prev" = --out-dir ] && out=$arg
      prev=$arg
    done
    if [[ $out =~ ^(${config.myConfig.modules.users.homeDir}/code/[^/]+/(worktrees/[^/]+|main))(/|$) ]]; then
      export SCCACHE_BASEDIRS=''${BASH_REMATCH[1]}
      export SCCACHE_SERVER_PORT=$((20000 + $(printf %s "$SCCACHE_BASEDIRS" | ${pkgs.coreutils}/bin/cksum | ${pkgs.coreutils}/bin/cut -d' ' -f1) % 20000))
    fi
    ${remoteLevel}
    ${startOrBypass}
    exec ${sccache} "$@"
  '';
  evict = pkgs.writeShellScript "sccache-cache-evict" ''
    set -euo pipefail
    cd ${cacheRoot}
    ${pkgs.findutils}/bin/find . -type f -printf '%A@ %s %p\0' | ${pkgs.coreutils}/bin/sort -z -n -r |
      ${pkgs.gawk}/bin/awk -v RS='\0' -v ORS='\0' -v cap=${
        toString (cfg.server.maxGiB * 1024 * 1024 * 1024)
      } '{ total += $2; if (total > cap) { sub(/^[^ ]+ [^ ]+ /, ""); print } }' |
      ${pkgs.findutils}/bin/xargs -0 -r ${pkgs.coreutils}/bin/rm -f --
    ${pkgs.findutils}/bin/find . -mindepth 1 -type d -empty -delete
  '';
in
{
  options.myConfig.modules.sccache = {
    enable = lib.mkEnableOption "sccache as the Rust compiler wrapper and CMake compiler launcher in every user session";
    cacheDir = lib.mkOption {
      type = lib.types.str;
      default = "$HOME/.cache/sccache";
      description = "Local disk cache directory shared by all checkouts of the user";
    };
    cacheSize = lib.mkOption {
      type = lib.types.str;
      default = "30G";
      description = "Size cap of the local cache, in sccache's SCCACHE_CACHE_SIZE form";
    };
    remote = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "10.77.0.1:8379";
      description = "host:port of the shared cache that a host with `server.enable` serves, read and written as the level behind the local disk through a local relay that answers every upstream failure as a miss within 3 s, so an outage leaves builds on the local disk";
    };
    server = {
      enable = lib.mkEnableOption "the shared compiler cache: an rclone WebDAV store on disk, swept hourly to its cap by last read, that answers only the listed wg-nexus peers";
      address = lib.mkOption {
        type = lib.types.str;
        default = "10.77.0.1";
        description = "Address the cache listens on, this host's wg-nexus address";
      };
      port = lib.mkOption {
        type = lib.types.port;
        default = 8379;
        description = "TCP port of the cache";
      };
      clients = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        description = "wg-nexus addresses allowed to read and write the cache; WireGuard binds each source address to one peer's key, so this list is the credential";
      };
      maxGiB = lib.mkOption {
        type = lib.types.ints.positive;
        default = 20;
        description = "Size cap of the cache in GiB, enforced by the hourly sweep";
      };
    };
  };
  config = lib.mkMerge [
    (lib.mkIf cfg.enable {
      environment.systemPackages = [ pkgs.sccache ];
      systemd.user.services.sccache-server = {
        description = "Shared sccache server on port 4226, outside every session and lease scope";
        wantedBy = [ "default.target" ];
        environment = {
          SCCACHE_START_SERVER = "1";
          SCCACHE_NO_DAEMON = "1";
          SCCACHE_IDLE_TIMEOUT = "0";
          SCCACHE_SERVER_PORT = "4226";
          SCCACHE_DIR = lib.replaceStrings [ "$HOME" ] [ "%h" ] cfg.cacheDir;
          SCCACHE_CACHE_SIZE = cfg.cacheSize;
          SCCACHE_BASEDIRS = "%h/code";
        }
        // lib.optionalAttrs (cfg.remote != null) {
          SCCACHE_MULTILEVEL_CHAIN = "disk,webdav";
          SCCACHE_WEBDAV_ENDPOINT = "http://127.0.0.1:${toString relayPort}";
        };
        serviceConfig = {
          ExecStart = sccache;
          Restart = "always";
          RestartSec = 2;
        };
      };
      environment.sessionVariables = {
        SCCACHE_DIR = cfg.cacheDir;
        SCCACHE_CACHE_SIZE = cfg.cacheSize;
        SCCACHE_BASEDIRS = "$HOME/code";
      }
      // lib.genAttrs [ "RUSTC_WRAPPER" "CMAKE_C_COMPILER_LAUNCHER" "CMAKE_CXX_COMPILER_LAUNCHER" ] (
        _: "${wrapper}"
      );
    })
    (lib.mkIf (cfg.enable && cfg.remote != null) {
      services.nginx = {
        enable = true;
        upstreams.sccache-remote = {
          servers.${cfg.remote} = { };
          extraConfig = "keepalive 16;";
        };
        virtualHosts.sccache-remote = {
          listen = [
            {
              addr = "127.0.0.1";
              port = relayPort;
            }
          ];
          extraConfig = "client_max_body_size 0;";
          locations."/".extraConfig = ''
            proxy_pass http://sccache-remote;
            proxy_http_version 1.1;
            proxy_set_header Connection "";
            proxy_connect_timeout 1s;
            proxy_send_timeout 5s;
            proxy_read_timeout 3s;
            proxy_request_buffering off;
            proxy_intercept_errors on;
            error_page 500 502 503 504 = @miss;
          '';
          locations."@miss".return = "404";
        };
      };
      systemd.services.sccache-remote-socket = {
        description = "Bridge ${relaySocket} to the compiler cache relay, for builds in network-less sandboxes";
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          ExecStart = "${lib.getExe pkgs.socat} UNIX-LISTEN:${relaySocket},fork,mode=0600,unlink-early TCP:127.0.0.1:${toString relayPort}";
          User = username;
          RuntimeDirectory = "sccache-remote";
          Restart = "always";
          RestartSec = 2;
        };
      };
    })
    (lib.mkIf cfg.server.enable {
      users = {
        users.sccache-cache = {
          isSystemUser = true;
          group = "sccache-cache";
        };
        groups.sccache-cache = { };
      };
      systemd = {
        services.sccache-cache = {
          description = "Serve the shared compiler cache over WebDAV on ${cfg.server.address}:${toString cfg.server.port}";
          wantedBy = [ "multi-user.target" ];
          after = [ "wireguard-wg-nexus.service" ];
          wants = [ "wireguard-wg-nexus.service" ];
          serviceConfig = {
            ExecStart = "${lib.getExe pkgs.rclone} serve webdav ${cacheRoot} --addr ${cfg.server.address}:${toString cfg.server.port}";
            User = "sccache-cache";
            StateDirectory = "sccache-cache";
            StateDirectoryMode = "0750";
            Restart = "always";
            RestartSec = 5;
          };
        };
        services.sccache-cache-evict = {
          description = "Delete the least recently read compiler cache entries above ${toString cfg.server.maxGiB} GiB";
          serviceConfig = {
            Type = "oneshot";
            User = "sccache-cache";
            ExecStart = evict;
          };
        };
        timers.sccache-cache-evict = {
          wantedBy = [ "timers.target" ];
          timerConfig.OnCalendar = "hourly";
        };
      };
      networking.firewall.extraInputRules = ''
        iifname "wg-nexus" ip saddr { ${lib.concatStringsSep ", " cfg.server.clients} } tcp dport ${toString cfg.server.port} accept
      '';
    })
  ];
}
