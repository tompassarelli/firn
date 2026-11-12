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
    githubInstallationTokenFile = lib.mkOption {
      type = lib.types.str;
      description = "Absolute path of the token file the broker reads fresh on each use for the GitHub credential, loaded by systemd as a credential so the broker never reads an operator's home";
    };
    threadsLedgerKeyFile = lib.mkOption {
      type = lib.types.str;
      description = "Absolute path of the threads ledger key, loaded by systemd as a credential for the ledger forward";
    };
    threadsLedgerHost = lib.mkOption {
      type = lib.types.str;
      description = "Host name of the threads ledger, whose key the broker's ssh trusts from the system known-hosts file";
    };
    threadsLedgerHostKey = lib.mkOption {
      type = lib.types.str;
      description = "Public host key of the threads ledger, in the form ssh_known_hosts reads";
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
    programs.ssh.knownHosts.threads-ledger = {
      hostNames = [ cfg.threadsLedgerHost ];
      publicKey = cfg.threadsLedgerHostKey;
    };
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
          "github-installation-token:${cfg.githubInstallationTokenFile}"
          "threads-ledger.key:${cfg.threadsLedgerKeyFile}"
        ];
        RuntimeDirectory = [
          "north-broker"
          "agent-brokers"
        ];
        RuntimeDirectoryMode = "0750";
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        PrivateDevices = true;
        RestrictAddressFamilies = [
          "AF_UNIX"
          "AF_INET"
          "AF_INET6"
        ];
        CapabilityBoundingSet = [ "" ];
        ExecStart = "${cfg.package}/bin/north broker serve --socket ${systemSocket} --policy ${cfg.policy} --agent-socket ${agentSocket} --agent-gid ${toString agent.gid}";
      };
    };
  };
}
