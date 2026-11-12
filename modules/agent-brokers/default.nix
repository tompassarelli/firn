{ config, lib, ... }:

let
  cfg = config.myConfig.modules.agent-brokers;
  agent = config.myConfig.modules.agent-user.name;
  operator = config.myConfig.modules.users.username;
  runDir = "/run/agent-brokers";
  forward = name: upstream: {
    sockets."agent-${name}" = {
      description = "Socket the agent user reaches the operator's ${name} broker through";
      wantedBy = [ "sockets.target" ];
      socketConfig = {
        ListenStream = "${runDir}/${name}.sock";
        Accept = true;
        SocketGroup = agent;
        SocketMode = "0660";
      };
    };
    services."agent-${name}@" = {
      description = "Forwards one agent connection to the operator's ${name} broker";
      serviceConfig = {
        ExecStart = "${config.systemd.package}/lib/systemd/systemd-socket-proxyd ${upstream}";
        StandardInput = "socket";
        User = operator;
      };
    };
  };
in
{
  options.myConfig.modules.agent-brokers = {
    enable = lib.mkEnableOption "system sockets that forward the agent user's connections to the operator's brokers, which stay the operator's and serve the agent";
    operatorUid = lib.mkOption {
      type = lib.types.ints.unsigned;
      description = "UID of the operator's account, whose runtime directory holds the GitHub broker's socket";
    };
    threadsSocket = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Socket of the operator's threads ledger that the agent user forwards to; no threads socket is created while null";
    };
  };
  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      (forward "github" "/run/user/${toString cfg.operatorUid}/north-gh-broker/broker.sock")
      (lib.mkIf (cfg.threadsSocket != null) (forward "threads" cfg.threadsSocket))
      {
        assertions = [
          {
            assertion = config.myConfig.modules.agent-user.enable;
            message = "agent-brokers forwards the agent user's connections, so myConfig.modules.agent-user must be enabled";
          }
        ];
        systemd.tmpfiles.rules = [ "d ${runDir} 0711 root root -" ];
      }
    ]
  );
}
