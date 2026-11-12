{ config, lib, ... }:

let
  cfg = config.myConfig.modules.agent-brokers;
  agent = config.myConfig.modules.agent-user;
  user = "north-broker";
  systemSocket = "/run/north-broker/broker.sock";
  agentSocket = "/run/agent-brokers/broker.sock";
in
{
  options.myConfig.modules.agent-brokers = {
    enable = lib.mkEnableOption "the system credential broker with a socket for the agent user of its own, group agent: the broker applies the agent's policy by the caller's uid, and no unit forwards as the operator";
    package = lib.mkOption {
      type = lib.types.package;
      description = "The north package whose broker serves both sockets";
    };
    policy = lib.mkOption {
      type = lib.types.str;
      description = "Absolute path of the broker's policy file, which names the grants of each caller";
    };
    githubAppFile = lib.mkOption {
      type = lib.types.str;
      description = "Absolute path of the GitHub App key file the broker mints the agent's tokens from, loaded by systemd as a credential so the broker never reads an operator's home";
    };
    threadsLedgerKeyFile = lib.mkOption {
      type = lib.types.str;
      description = "Absolute path of the threads ledger key, loaded by systemd as a credential for the ledger forward";
    };
  };
  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = agent.enable;
        message = "agent-brokers serves the agent user, so myConfig.modules.agent-user must be enabled";
      }
      {
        assertion = agent.gid != null;
        message = "agent-brokers grants the agent socket by group number, so myConfig.modules.agent-user.gid must be set";
      }
    ];
    users.users.${user} = {
      isSystemUser = true;
      group = user;
      home = "/var/empty";
      description = "north credential broker";
    };
    users.groups.${user} = { };
    systemd.services.north-broker = {
      description = "north credential broker: the system socket for operator tools and the agent socket for the agent user";
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "simple";
        Restart = "on-failure";
        User = user;
        Group = user;
        SupplementaryGroups = [ agent.name ];
        LoadCredential = [
          "github-app.yaml:${cfg.githubAppFile}"
          "threads-ledger.key:${cfg.threadsLedgerKeyFile}"
        ];
        RuntimeDirectory = [
          "north-broker"
          "agent-brokers"
        ];
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        PrivateTmp = true;
        CapabilityBoundingSet = [ "" ];
        ExecStart = "${cfg.package}/bin/north broker serve --socket ${systemSocket} --policy ${cfg.policy} --agent-socket ${agentSocket} --agent-gid ${toString agent.gid}";
      };
    };
  };
}
