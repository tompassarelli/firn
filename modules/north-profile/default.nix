{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.myConfig.modules.north-profile;
  context = builtins.fromJSON (builtins.readFile ./context.json);
  contextWindow =
    if (context.window < context.modelMaxContextWindow) then
      context.window
    else
      context.modelMaxContextWindow;
  claudeProjection = builtins.toJSON (
    builtins.fromJSON (builtins.readFile ./claude-hooks.json) // { autoCompactWindow = contextWindow; }
  );
in
{
  options.myConfig.modules.north-profile.enable =
    lib.mkEnableOption "Publish shared agent surfaces at ~/.agents";
  config = lib.mkIf cfg.enable {
    environment.etc."north/agent-context.json".text = builtins.toJSON {
      window = contextWindow;
      inherit (context) autoCompactTokenLimit;
    };
    home-manager.users.${config.myConfig.modules.users.username} = hm: {
      home = {
        activation.projectNorthClaudeHooks = hm.config.lib.dag.entryAfter [ "writeBoundary" ] ''
          run ${pkgs.coreutils}/bin/env CHMOD_BIN=${pkgs.coreutils}/bin/chmod FLOCK_BIN=${pkgs.util-linux}/bin/flock JQ_BIN=${pkgs.jq}/bin/jq MKDIR_BIN=${pkgs.coreutils}/bin/mkdir MV_BIN=${pkgs.coreutils}/bin/mv REALPATH_BIN=${pkgs.coreutils}/bin/realpath RM_BIN=${pkgs.coreutils}/bin/rm ${pkgs.writeShellScript "north-claude-hook-projector" (builtins.readFile ./claude-hook-projector.sh)} ${pkgs.writeText "north-claude-hooks.json" claudeProjection} $HOME/.claude/settings.json
        '';
        file = {
          ".agents/AGENTS.md".source =
            hm.config.lib.file.mkOutOfStoreSymlink "${hm.config.home.homeDirectory}/.local/state/north/agents/current/instructions/shared/AGENTS.md";
          ".agents/hooks".source =
            hm.config.lib.file.mkOutOfStoreSymlink "${hm.config.home.homeDirectory}/.local/state/north/agents/current/provider-hooks";
          ".agents/skills".source =
            hm.config.lib.file.mkOutOfStoreSymlink "${hm.config.home.homeDirectory}/.local/state/north/agents/current/skills/shared";
          "code/AGENTS.md".source =
            hm.config.lib.file.mkOutOfStoreSymlink "${hm.config.home.homeDirectory}/.local/state/north/agents/current/instructions/code/AGENTS.md";
        };
      };
    };
  };
}
