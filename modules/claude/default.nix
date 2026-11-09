{ config, lib, ... }:

let
  cfg = config.myConfig.modules.claude;
  username = config.myConfig.modules.users.username;
  accountLabels = [
    "a"
    "b"
    "c"
    "d"
    "e"
  ];
  launcherNames = [
    "claude"
    "claude-as"
  ]
  ++ map (label: "claude-${label}") accountLabels;
in
{
  options.myConfig.modules.claude.enable = lib.mkEnableOption "Claude Code fallback coding agent";
  config = lib.mkIf cfg.enable {
    home-manager.users.${username} = { config, ... }: {
      home.file = {
        ".claude/CLAUDE.md".source =
          config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.local/state/north/agents/current/instructions/shared/AGENTS.md";
        ".claude/agents".source =
          config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/code/north/main/harness/claude/agents";
      }
      // lib.genAttrs (map (name: ".local/bin/${name}") launcherNames) (_: {
        source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.local/share/firn/bin/claude";
      });
    };
  };
}
