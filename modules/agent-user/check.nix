{
  lib,
  pkgs,
  enabled,
  disabled,
}:

let
  e = enabled.config;
  d = disabled.config;
  managed = "claude-code/managed-settings.json";
  broker = e.systemd.services.north-broker.serviceConfig.ExecStart;
  runtimeLink = e.system.activationScripts.agent-runtime-link.text;
  runtime = e.myConfig.modules.agent-runtime-link.path;
  hooks = import ../agent-claude-managed/hooks.nix runtime;
  commandsOf = entries: lib.concatMap (entry: map (hook: hook.command) entry.hooks) entries;
  hookCommands = commandsOf (lib.concatMap (event: event) (lib.attrValues hooks));
  gatedCommands = commandsOf (hooks.PreToolUse ++ hooks.PermissionRequest);
  brokerService = e.systemd.services.north-broker.serviceConfig;
  agentUnits = lib.filterAttrs (
    name: _: name == "north-broker" || lib.hasPrefix "agent-" name
  ) e.systemd.services;
  runsAsOperator = lib.any (unit: (unit.serviceConfig.User or null) == "operator") (
    lib.attrValues agentUnits
  );
  starter = e.systemd.services.north-agent-starts;
  starterWords = lib.splitString " " (
    builtins.unsafeDiscardStringContext starter.serviceConfig.ExecStart
  );
  starterValue =
    flag: lib.elemAt starterWords (lib.lists.findFirstIndex (word: word == flag) 0 starterWords + 1);
  rule = builtins.unsafeDiscardStringContext e.security.polkit.extraConfig;
  checks = {
    "the north checkout is a oneshot as the agent user, cloning a credential-free https URL into the agent home" =
      e.systemd.services.agent-north-checkout.serviceConfig.Type == "oneshot"
      && e.systemd.services.agent-north-checkout.serviceConfig.User == "agent"
      && lib.hasPrefix "/home/agent/" e.myConfig.modules.agent-user.checkout.path
      && !(lib.hasInfix "@" e.myConfig.modules.agent-user.checkout.url)
      && !(e.systemd.services.agent-north-checkout.serviceConfig ? EnvironmentFile);
    "a host with no agent login runs no north checkout" = !(d.systemd.services ? agent-north-checkout);
    "the agent user has a 0700 home and lingers" =
      e.users.users.agent.homeMode == "0700"
      && e.users.users.agent.home == "/home/agent"
      && e.users.users.agent.linger;
    "the agent user has no supplementary groups" = e.users.users.agent.extraGroups == [ ];
    "the operator is not a member of the agent group" =
      !(lib.elem "operator" e.users.groups.agent.members);
    "the agent user is not a Nix trusted user" = !(lib.elem "agent" e.nix.settings.trusted-users);
    "the agent user is a member of no group but its own" =
      !(lib.any (group: lib.elem "agent" group.members) (lib.attrValues e.users.groups));
    "the managed Claude settings are a symlink into the root-owned store" =
      e.environment.etc.${managed}.mode == "symlink"
      && lib.hasPrefix "/nix/store/" (toString e.environment.etc.${managed}.source);
    "the managed hooks run env and north from the runtime link, and dispatch every tool" =
      hookCommands != [ ]
      && lib.all (command: lib.hasInfix "${runtime}/env " command) hookCommands
      && lib.any (command: lib.hasSuffix " north hook dispatch" command) hookCommands;
    "every gated hook blocks when the runtime env is missing" =
      gatedCommands != [ ]
      && lib.all (
        command: lib.hasPrefix "test -x ${runtime}/env && test -x ${runtime}/north || exit 2; " command
      ) gatedCommands;
    "the broker serves the agent on its own socket, by the agent's group number" =
      lib.hasInfix "--agent-socket /run/agent-brokers/broker.sock" broker
      && lib.hasInfix "--agent-gid 1500" broker;
    "the broker runs as its own static user, in the agent group, with no capability" =
      brokerService.User == "north-broker"
      && brokerService.Group == "north-broker"
      && brokerService.SupplementaryGroups == [ "agent" ]
      && brokerService.CapabilityBoundingSet == [ "" ]
      && brokerService.NoNewPrivileges
      && brokerService.ProtectSystem == "strict"
      && brokerService.ProtectHome
      && brokerService.PrivateTmp
      && brokerService.PrivateDevices;
    "the broker's runtime directories are 0750, the mode its own socket directory check requires" =
      brokerService.RuntimeDirectoryMode == "0750";
    "the broker loads its credentials from paths, never from an operator's home" =
      lib.length brokerService.LoadCredential == 2
      && lib.hasPrefix "github-installation-token:" (lib.head brokerService.LoadCredential)
      && lib.hasPrefix "threads-ledger.key:" (lib.last brokerService.LoadCredential);
    "the ledger host's key is in the system known-hosts file, so the broker's ssh needs no home" =
      e.programs.ssh.knownHosts ? threads-ledger
      && lib.elem "ledger.fixture.invalid" e.programs.ssh.knownHosts.threads-ledger.hostNames;
    "no unit runs as the operator, so the broker sees the agent's own credentials" = !runsAsOperator;
    "the cache seed runs once, behind a stamp only root writes" =
      e.systemd.services.agent-cache-seed.unitConfig.ConditionPathExists
      == "!/var/lib/agent-user/caches-seeded";
    "the runtime link is laid by the activation, in the operator's directory, and only while absent" =
      lib.hasInfix "/var/lib/agent-runtime/current" runtimeLink
      && lib.hasInfix "install -d -o operator" runtimeLink
      && lib.hasInfix "[ ! -L /var/lib/agent-runtime/current ]" runtimeLink;
    "the starter runs as the operator, only store paths, with no environment file and no PATH outside the store, and reads requests from its own 0700 state directory" =
      starter.serviceConfig.User == "operator"
      && lib.all (lib.hasPrefix "/nix/store/") [
        (lib.head starterWords)
        (starterValue "--entry")
        (starterValue "--machinectl")
      ]
      && !(starter.serviceConfig ? EnvironmentFile)
      && !(starter.serviceConfig ? WorkingDirectory)
      && lib.all (lib.hasPrefix "/nix/store/") (lib.splitString ":" starter.environment.PATH)
      && starterValue "--requests" == "/var/lib/${starter.serviceConfig.StateDirectory}"
      && starter.serviceConfig.StateDirectoryMode == "0700";
    "no process but the starter's ancestors can ptrace it" =
      e.boot.kernel.sysctl."kernel.yama.ptrace_scope" >= 1;
    "polkit admits the agent's host shell only to the starter unit, its fixed entry and a checked caller, and refuses every other" =
      lib.hasInfix "subject.system_unit == \"north-agent-starts.service\"" rule
      && lib.hasInfix "subject.user == \"operator\"" rule
      && lib.hasInfix "action.lookup(\"command_line\") == \"${starterValue "--entry"}\"" rule
      && lib.hasInfix "polkit.spawn(" rule
      && lib.hasInfix "return polkit.Result.NO;" rule;
    "a host with no agent login runs no starter" = !(d.systemd.services ? north-agent-starts);
    "a host with no agent login has no agent user" =
      !(d.users.users ? agent) && !(d.users.groups ? agent);
    "a host with no agent login writes no managed Claude settings" = !(d.environment.etc ? ${managed});
    "a host with no agent login runs no broker for the agent" =
      !(d.systemd.services ? north-broker) && !(d.users.users ? north-broker);
    "a host with no agent login seeds no caches" = !(d.systemd.services ? agent-cache-seed);
    "the operator's login name is in /etc/north/operator, so a check run as anyone else is confined" =
      e.environment.etc."north/operator".text == "operator";
    "a host with no agent login lays no runtime link" =
      !(d.system.activationScripts ? agent-runtime-link);
    "a host with no agent login names no operator for offloaded checks" =
      !(d.environment.etc ? "north/operator");
  };
  failed = lib.attrNames (lib.filterAttrs (_: ok: !ok) checks);
in
if failed == [ ] then
  pkgs.runCommand "firn-agent-login" { } "touch $out"
else
  throw "agent login check failed: ${lib.concatStringsSep "; " failed}"
