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
      home.activation.installCaveman = config.lib.dag.entryAfter [ "writeBoundary" "linkClaudeSettings" ] "CLAUDE=${pkgs.master.claude-code}/bin/claude\nWANT=37c28ebb1e0a\nGITC=$(mktemp)\n${pkgs.git}/bin/git config -f \"$GITC\" url.\"https://github.com/\".insteadOf \"git@github.com:\"\nif [ ! -e $HOME/.claude/plugins/cache/caveman ]; then\n  run timeout 90 $CLAUDE plugin marketplace add tompassarelli/caveman || true\n  run timeout 90 env GIT_CONFIG_GLOBAL=\"$GITC\" $CLAUDE plugin install caveman@caveman || true\nelif [ ! -e $HOME/.claude/plugins/cache/caveman/caveman/$WANT ]; then\n  run timeout 90 $CLAUDE plugin marketplace update caveman || true\n  run timeout 90 $CLAUDE plugin uninstall caveman@caveman || true\n  run timeout 90 env GIT_CONFIG_GLOBAL=\"$GITC\" $CLAUDE plugin install caveman@caveman || true\nfi\nrm -f \"$GITC\"\n";
      home.activation.registerMcpServers = config.lib.dag.entryAfter [ "writeBoundary" ] "CLAUDE=${pkgs.master.claude-code}/bin/claude\nLIFE=$HOME/.local/state/lodestar\nif ! $CLAUDE mcp get fram 2>/dev/null | grep -q FRAM_LOG; then\n  $CLAUDE mcp remove fram -s user >/dev/null 2>&1 || true\n  run timeout 30 $CLAUDE mcp add fram -s user -e FRAM_LOG=$LIFE/claims.log -e FRAM_THREADS=$LIFE/threads -- $HOME/code/fram/bin/fram-mcp || true\nfi\nif ! $CLAUDE mcp get lodestar >/dev/null 2>&1; then\n  run timeout 30 $CLAUDE mcp add lodestar -s user -- $HOME/code/lodestar/bin/lodestar-mcp || true\nfi\nif ! $CLAUDE mcp get linear-mcp-msa-old >/dev/null 2>&1; then\n  run timeout 30 $CLAUDE mcp add --transport http linear-mcp-msa-old https://mcp.linear.app/mcp -s user || true\nfi\nif ! $CLAUDE mcp get linear-mcp-msa-new >/dev/null 2>&1; then\n  run timeout 30 $CLAUDE mcp add --transport http linear-mcp-msa-new https://mcp.linear.app/mcp -s user || true\nfi\n";
    });
  };
}
