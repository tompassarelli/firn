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
in
{
  options.myConfig.modules.agent-claude-managed = {
    enable = lib.mkEnableOption "Claude Code's managed settings under /etc, root-owned in the Nix store, so an agent session reads its hooks and permissions from them and cannot change them";
    settings = lib.mkOption {
      inherit (json) type;
      default = { };
      description = "Hooks and permissions written to /etc/claude-code/managed-settings.json, the highest-precedence Claude Code source; the guards that let only managed hooks and rules run are set by the module";
    };
  };
  config = lib.mkIf cfg.enable {
    environment.etc."claude-code/managed-settings.json".source = json.generate "managed-settings.json" (
      lib.recursiveUpdate cfg.settings guards
    );
  };
}
