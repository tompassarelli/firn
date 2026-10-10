{ config, lib, pkgs, ... }:

((username: {
  options.myConfig.modules.claude.enable = lib.mkEnableOption "Claude Code fallback coding agent";
  config = lib.mkIf config.myConfig.modules.claude.enable {
    home-manager.users.${username} = ({ config, ... }: {
      home.file = {
        ".claude/CLAUDE.md".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.local/state/north/agents/current/instructions/shared/AGENTS.md";
        ".claude/agents".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/code/north/main/socrates/claude/agents";
      };
    });
  };
}) config.myConfig.modules.users.username)
