{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.myConfig.modules.agent-claude-managed;
  json = pkgs.formats.json { };
  guards = {
    allowManagedHooksOnly = true;
    allowManagedPermissionRulesOnly = true;
  }
  // lib.optionalAttrs (!cfg.allowBypass) { disableBypassPermissionsMode = "disable"; };
  hooks = import ./hooks.nix cfg.runtime;
in
{
  options.myConfig.modules.agent-claude-managed = {
    enable = lib.mkEnableOption "Claude Code's managed settings under /etc, root-owned in the Nix store, so an agent session runs the north guard hooks and reads its permissions from them and cannot change them";
    settings = lib.mkOption {
      inherit (json) type;
      default = { };
      description = "Permissions and other settings written to /etc/claude-code/managed-settings.json, the highest-precedence Claude Code source; the north guard hooks and the guards that let only managed hooks and rules run are set by the module";
    };
    allowBypass = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Leave bypass-permissions mode available on this host, so `north fleet launch` can start its sessions with bypass; the file is machine-wide, so a host that sets this lets every Claude account on it start in bypass mode";
    };
    runtime = lib.mkOption {
      type = lib.types.str;
      default = config.myConfig.modules.agent-runtime-link.path;
      description = "Runtime link that the hook commands run north from, the operator-owned link the agent user follows; the hooks run env from /run/current-system/sw/bin, since the published runtime holds only north and verify-north";
    };
  };
  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = (cfg.settings.permissions.allow or [ ]) != [ ];
        message = "agent-claude-managed lets only managed permission rules run, so settings.permissions.allow must hold the rules agent sessions need, or every tool call asks";
      }
    ];
    environment.etc."claude-code/managed-settings.json".source = json.generate "managed-settings.json" (
      lib.recursiveUpdate (lib.recursiveUpdate cfg.settings { inherit hooks; }) guards
    );
  };
}
