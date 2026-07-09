{ config, lib, pkgs, ... }:

let
  username = config.myConfig.modules.users.username;
in
{
  options.myConfig.modules.claude.enable = lib.mkEnableOption "Claude Code CLI configuration";
  config = lib.mkIf config.myConfig.modules.claude.enable {
    environment.systemPackages = [ pkgs.claude-code-latest ];
    home-manager.users.${username} = ({ config, ... }: {
      home.file = {
        ".claude/commands".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/code/nixos-config/dotfiles/claude/commands";
        ".claude/skills".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/code/nixos-config/dotfiles/claude/skills";
        ".claude/CLAUDE.md".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/code/nixos-config/dotfiles/claude/CLAUDE.md";
        ".claude/hooks".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/code/nixos-config/dotfiles/claude/hooks";
        ".claude/agents".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/code/nixos-config/dotfiles/claude/agents";
        "code/CLAUDE.md".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/code/nixos-config/dotfiles/code/CLAUDE.md";
        ".config/caveman/config.json".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/code/nixos-config/dotfiles/caveman/config.json";
      };
      home.activation.linkClaudeSettings = config.lib.dag.entryAfter [ "writeBoundary" ] "run ln -sfn ${config.home.homeDirectory}/code/nixos-config/dotfiles/claude/settings.json $HOME/.claude/settings.json\n";
      home.activation.installCaveman = config.lib.dag.entryAfter [ "writeBoundary" "linkClaudeSettings" ] "CLAUDE=${pkgs.claude-code-latest}/bin/claude\nWANT=37c28ebb1e0a\nGITC=$(run mktemp)\nrun ${pkgs.git}/bin/git config -f \"$GITC\" url.\"https://github.com/\".insteadOf \"git@github.com:\"\nif [ ! -e $HOME/.claude/plugins/cache/caveman ]; then\n  run timeout 90 $CLAUDE plugin marketplace add tompassarelli/caveman || true\n  run timeout 90 env GIT_CONFIG_GLOBAL=\"$GITC\" $CLAUDE plugin install caveman@caveman || true\nelif [ ! -e $HOME/.claude/plugins/cache/caveman/caveman/$WANT ]; then\n  run timeout 90 $CLAUDE plugin marketplace update caveman || true\n  run timeout 90 $CLAUDE plugin uninstall caveman@caveman || true\n  run timeout 90 env GIT_CONFIG_GLOBAL=\"$GITC\" $CLAUDE plugin install caveman@caveman || true\n  run find $HOME/.claude/plugins/cache/caveman/caveman -mindepth 1 -maxdepth 1 ! -name \"$WANT\" -exec rm -rf {} + || true\nfi\nrun rm -f \"$GITC\"\n";
      home.activation.registerMcpServers = config.lib.dag.entryAfter [ "writeBoundary" ] "CLAUDE=${pkgs.claude-code-latest}/bin/claude\nLIFE=$HOME/.local/state/north\nif ! $CLAUDE mcp get fram 2>/dev/null | grep -q FRAM_LOG; then\n  run timeout 30 $CLAUDE mcp remove fram -s user >/dev/null 2>&1 || true\n  run timeout 30 $CLAUDE mcp add fram -s user -e FRAM_LOG=$LIFE/claims.log -e FRAM_THREADS=$LIFE/threads -- $HOME/code/fram/bin/fram-mcp || true\nfi\nif ! $CLAUDE mcp get north >/dev/null 2>&1; then\n  run timeout 30 $CLAUDE mcp add north -s user -- $HOME/code/north/bin/tern-mcp || true\nfi\nif ! $CLAUDE mcp get linear-mcp-msa-new >/dev/null 2>&1; then\n  run timeout 30 $CLAUDE mcp add --transport http linear-mcp-msa-new https://mcp.linear.app/mcp -s user || true\nfi\n";
    });
  };
}
