{ config, lib, pkgs, ... }:

let
  username = config.myConfig.modules.users.username;
in
{
  options.myConfig.modules.claude.enable = lib.mkEnableOption "Claude Code CLI configuration";
  config = lib.mkIf config.myConfig.modules.claude.enable {
    environment.systemPackages = [ pkgs.master.claude-code ];
    home-manager.users.${username} = ({ config, ... }: {
      home.file = {
        ".claude/settings.json".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/code/nixos-config/dotfiles/claude/settings.json";
        ".claude/commands".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/code/nixos-config/dotfiles/claude/commands";
        ".claude/skills".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/code/nixos-config/dotfiles/claude/skills";
        ".claude/CLAUDE.md".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/code/nixos-config/dotfiles/claude/CLAUDE.md";
        ".claude/hooks".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/code/nixos-config/dotfiles/claude/hooks";
        "code/CLAUDE.md".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/code/nixos-config/dotfiles/code/CLAUDE.md";
        ".config/caveman/config.json".text = builtins.toJSON {
          defaultMode = "lite";
        };
      };
      home.activation.installCaveman = config.lib.dag.entryAfter [ "writeBoundary" ] "if [ ! -e $HOME/.claude/plugins/cache/caveman ]; then\n  run timeout 90 ${pkgs.master.claude-code}/bin/claude plugin marketplace add JuliusBrussee/caveman || true\n  run timeout 90 ${pkgs.master.claude-code}/bin/claude plugin install caveman@caveman || true\nfi\n";
    });
  };
}
