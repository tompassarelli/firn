{ config, lib, pkgs, ... }:

((cfg: ((homeDir: ((username: ((description: ((path: {
  options.myConfig.modules.socrates-chat = {
    enable = lib.mkEnableOption description;
    homeserver = lib.mkOption {
      type = lib.types.str;
      description = "Matrix homeserver URL";
    };
    tomUserId = lib.mkOption {
      type = lib.types.str;
      description = "Matrix user id authorized to send input to agent sessions";
    };
    tokenFile = lib.mkOption {
      type = lib.types.str;
      description = "Path to the rendered appservice token, supplied by the private overlay";
    };
    proxyPane = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Optional proxy tmux socket and pane, in socket:pane form";
    };
    watches = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Run the watch and ETA engine; enable it on exactly one host, one with gh signed in";
    };
  };
  config = lib.mkIf cfg.enable {
    home-manager.users.${username} = ({ ... }: {
      systemd.user.services.socrates-chat = {
        Unit = {
          Description = description;
        };
        Service = {
          Type = "simple";
          Restart = "always";
          RestartSec = "10s";
          Environment = lib.concatLists [
            [
              path
              "SOCRATES_CHAT_HOMESERVER=${cfg.homeserver}"
              "SOCRATES_CHAT_TOM_USER_ID=${cfg.tomUserId}"
              "SOCRATES_CHAT_TOKEN_FILE=${cfg.tokenFile}"
            ]
            (lib.optional (cfg.proxyPane != null) "SOCRATES_CHAT_PROXY_PANE=${cfg.proxyPane}")
            (lib.optional cfg.watches "SOCRATES_CHAT_WATCHES=1")
          ];
          ExecStart = "${homeDir}/.local/share/north/bin/socrates-chat run";
        };
        Install = {
          WantedBy = [ "default.target" ];
        };
      };
      systemd.user.services.agents-flow-stall = lib.mkIf cfg.watches {
        Unit = {
          Description = "Report stalled repository landings";
        };
        Service = {
          Type = "oneshot";
          Environment = [ path ];
          ExecStart = "${homeDir}/.local/share/north/bin/agents flow --stall-alert";
        };
      };
      systemd.user.timers.agents-flow-stall = lib.mkIf cfg.watches {
        Unit = {
          Description = "Check repository landing progress every five minutes";
        };
        Timer = {
          OnCalendar = "*-*-* *:00/5:00";
          Persistent = true;
        };
        Install = {
          WantedBy = [ "timers.target" ];
        };
      };
    });
  };
}) "PATH=/run/wrappers/bin:/run/current-system/sw/bin:${homeDir}/.local/share/firn/bin:${homeDir}/.local/share/north/bin:${lib.makeBinPath [
    pkgs.bun
    pkgs.gh
    pkgs.git
    pkgs.python3
    pkgs.tmux
    pkgs.websocat
    pkgs.jq
    pkgs.sqlite
    pkgs.ripgrep
    pkgs.iproute2
    pkgs.coreutils
  ]}")) "Socrates chat relay for local agent sessions")) config.myConfig.modules.users.username)) config.myConfig.modules.users.homeDir)) config.myConfig.modules.socrates-chat)
