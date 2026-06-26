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
        ".claude/commands".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/code/nixos-config/dotfiles/claude/commands";
        ".claude/skills".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/code/nixos-config/dotfiles/claude/skills";
        ".claude/CLAUDE.md".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/code/nixos-config/dotfiles/claude/CLAUDE.md";
        ".claude/hooks".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/code/nixos-config/dotfiles/claude/hooks";
        "code/CLAUDE.md".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/code/nixos-config/dotfiles/code/CLAUDE.md";
        ".config/caveman/config.json".text = builtins.toJSON {
          defaultMode = "full";
        };
      };
      home.activation.linkClaudeSettings = config.lib.dag.entryAfter [ "writeBoundary" ] "run ln -sfn ${config.home.homeDirectory}/code/nixos-config/dotfiles/claude/settings.json $HOME/.claude/settings.json\n";
      home.activation.installCaveman = config.lib.dag.entryAfter [ "writeBoundary" ] "if [ ! -e $HOME/.claude/plugins/cache/caveman ]; then\n  run timeout 90 ${pkgs.master.claude-code}/bin/claude plugin marketplace add tompassarelli/caveman || true\n  run timeout 90 ${pkgs.master.claude-code}/bin/claude plugin install caveman@caveman || true\nfi\n";
      home.activation.registerMcpServers = config.lib.dag.entryAfter [ "writeBoundary" ] "CLAUDE=${pkgs.master.claude-code}/bin/claude\nLIFE=$HOME/.local/state/lodestar\nif ! $CLAUDE mcp get fram 2>/dev/null | grep -q FRAM_LOG; then\n  $CLAUDE mcp remove fram -s user >/dev/null 2>&1 || true\n  run timeout 30 $CLAUDE mcp add fram -s user -e FRAM_LOG=$LIFE/claims.log -e FRAM_THREADS=$LIFE/threads -- $HOME/code/fram/bin/fram-mcp || true\nfi\nif ! $CLAUDE mcp get lodestar >/dev/null 2>&1; then\n  run timeout 30 $CLAUDE mcp add lodestar -s user -- $HOME/code/lodestar/bin/lodestar-mcp || true\nfi\n";
    });
  };
}
