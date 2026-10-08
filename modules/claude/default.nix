{ config, lib, pkgs, ... }:

((username: {
  options.myConfig.modules.claude.enable = lib.mkEnableOption "Claude Code fallback coding agent";
  config = lib.mkIf config.myConfig.modules.claude.enable {
    environment.systemPackages = [
      (pkgs.unstable.claude-code.overrideAttrs (old: {
        version = "2.1.293";
        src = pkgs.fetchurl {
          url = "https://downloads.claude.ai/claude-code-releases/2.1.293/linux-x64/claude.zst";
          hash = "sha256-JXhto0fDBkHcbFBzPQkNd8tUDxBaYa9+mJW1bjn+FqU=";
        };
      }))
    ];
    home-manager.users.${username} = ({ config, ... }: {
      home.file = {
        ".claude/CLAUDE.md".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.local/state/north/agents/current/instructions/shared/AGENTS.md";
        ".claude/agents".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/code/nixos-config/main/dotfiles/agents/claude/agents";
      };
    });
  };
}) config.myConfig.modules.users.username)
