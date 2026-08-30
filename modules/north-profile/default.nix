{ config, lib, pkgs, ... }:

((username: ((claudeHookProjection: ((claudeHookProjector: {
  options.myConfig.modules.north-profile.enable = lib.mkEnableOption "Publish shared agent surfaces at ~/.agents";
  config = lib.mkIf config.myConfig.modules.north-profile.enable {
    home-manager.users.${username} = ({ config, ... }: {
      home.file = {
        ".agents/AGENTS.md".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.local/state/north/agents/current/instructions/shared/AGENTS.md";
        ".agents/skills".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.local/state/north/agents/current/skills/shared";
        ".agents/hooks".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.local/state/north/agents/current/provider-hooks";
        "code/AGENTS.md".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.local/state/north/agents/current/instructions/code/AGENTS.md";
      };
      home.activation.projectNorthClaudeHooks = config.lib.dag.entryAfter [ "writeBoundary" ] "run ${pkgs.coreutils}/bin/env CHMOD_BIN=${pkgs.coreutils}/bin/chmod FLOCK_BIN=${pkgs.util-linux}/bin/flock JQ_BIN=${pkgs.jq}/bin/jq MKDIR_BIN=${pkgs.coreutils}/bin/mkdir MV_BIN=${pkgs.coreutils}/bin/mv REALPATH_BIN=${pkgs.coreutils}/bin/realpath RM_BIN=${pkgs.coreutils}/bin/rm ${claudeHookProjector} ${claudeHookProjection} $HOME/.claude/settings.json\n";
    });
  };
}) (pkgs.writeShellScript "north-claude-hook-projector" (builtins.readFile ./claude-hook-projector.sh)))) (pkgs.writeText "north-claude-hooks.json" (builtins.readFile ./claude-hooks.json)))) config.myConfig.modules.users.username)
