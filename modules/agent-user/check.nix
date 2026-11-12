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
  github = e.systemd.sockets.agent-github.socketConfig;
  runtimeLink = e.system.activationScripts.agent-runtime-link.text;
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
    "the managed Claude settings are a store file that only root writes" =
      e.environment.etc.${managed}.user == "root" && e.environment.etc.${managed}.mode == "symlink";
    "the GitHub broker's socket is group agent, and its forward runs as the operator" =
      github.SocketGroup == "agent"
      && github.SocketMode == "0660"
      && e.systemd.services."agent-github@".serviceConfig.User == "operator";
    "the threads ledger's socket exists once its upstream is named" = e.systemd.sockets ? agent-threads;
    "the cache seed runs once, behind a stamp only root writes" =
      e.systemd.services.agent-cache-seed.unitConfig.ConditionPathExists
      == "!/var/lib/agent-user/caches-seeded";
    "the runtime link is laid by the activation, in the operator's directory" =
      lib.hasInfix "/var/lib/agent-runtime/current" runtimeLink
      && lib.hasInfix "install -d -o operator" runtimeLink;
    "a host with no agent login has no agent user" =
      !(d.users.users ? agent) && !(d.users.groups ? agent);
    "a host with no agent login writes no managed Claude settings" = !(d.environment.etc ? ${managed});
    "a host with no agent login opens no agent broker socket" = !(d.systemd.sockets ? agent-github);
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
