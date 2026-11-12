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
    disableBypassPermissionsMode = "disable";
  };
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
    runtime = lib.mkOption {
      type = lib.types.str;
      default = config.myConfig.modules.agent-runtime-link.path;
      description = "Runtime link that the hook commands run env and north from, the operator-owned link the agent user follows";
    };
  };
  config = lib.mkIf cfg.enable {
    environment.etc."claude-code/managed-settings.json".source = json.generate "managed-settings.json" (
      lib.recursiveUpdate (lib.recursiveUpdate cfg.settings { inherit hooks; }) guards
    );
  };
}
