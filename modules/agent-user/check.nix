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
  hookCommands = lib.concatMap (
    entries: lib.concatMap (entry: map (hook: hook.command) entry.hooks) entries
  ) (lib.attrValues (import ../agent-claude-managed/hooks.nix runtime));
  agentUnits = lib.filterAttrs (
    name: _: name == "north-broker" || lib.hasPrefix "agent-" name
  ) e.systemd.services;
  runsAsOperator = lib.any (unit: (unit.serviceConfig.User or null) == "operator") (
    lib.attrValues agentUnits
  );
  checks = {
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
      && lib.all (command: lib.hasPrefix "${runtime}/env " command) hookCommands
      && lib.any (command: lib.hasSuffix " north hook dispatch" command) hookCommands;
    "the broker serves the agent on its own socket, by the agent's group number" =
      lib.hasInfix "--agent-socket /run/agent-brokers/broker.sock" broker
      && lib.hasInfix "--agent-gid 1500" broker;
    "no unit runs as the operator, so the broker sees the agent's own credentials" = !runsAsOperator;
    "the cache seed runs once, behind a stamp only root writes" =
      e.systemd.services.agent-cache-seed.unitConfig.ConditionPathExists
      == "!/var/lib/agent-user/caches-seeded";
    "the runtime link is laid by the activation, in the operator's directory, and only while absent" =
      lib.hasInfix "/var/lib/agent-runtime/current" runtimeLink
      && lib.hasInfix "install -d -o operator" runtimeLink
      && lib.hasInfix "[ ! -L /var/lib/agent-runtime/current ]" runtimeLink;
    "a host with no agent login has no agent user" =
      !(d.users.users ? agent) && !(d.users.groups ? agent);
    "a host with no agent login writes no managed Claude settings" = !(d.environment.etc ? ${managed});
    "a host with no agent login runs no broker for the agent" = !(d.systemd.services ? north-broker);
    "a host with no agent login seeds no caches" = !(d.systemd.services ? agent-cache-seed);
    "a host with no agent login lays no runtime link" =
      !(d.system.activationScripts ? agent-runtime-link);
  };
  failed = lib.attrNames (lib.filterAttrs (_: ok: !ok) checks);
in
if failed == [ ] then
  pkgs.runCommand "firn-agent-login" { } "touch $out"
else
  throw "agent login check failed: ${lib.concatStringsSep "; " failed}"
