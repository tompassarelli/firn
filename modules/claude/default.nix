{ config, lib, pkgs, inputs, flakeRoot, ... }:

let
  username = config.myConfig.modules.users.username;
  claudePackage = if pkgs.stdenv.hostPlatform.isDarwin then pkgs.master.claude-code else pkgs.claude-code-latest;
  psBin = if pkgs.stdenv.hostPlatform.isDarwin then "/bin/ps" else "${pkgs.procps}/bin/ps";
  northPkg = inputs.north.packages."${pkgs.stdenv.hostPlatform.system}".default;
  framPkg = inputs.fram.packages."${pkgs.stdenv.hostPlatform.system}".default;
  claudeSettingsSeed = pkgs.writeText "claude-settings.json" (builtins.readFile "${flakeRoot}/dotfiles/claude/settings.json");
  claudeSettingsSeeder = pkgs.writeShellScript "claude-settings-seed" (builtins.readFile "${flakeRoot}/scripts/claude-settings-seed.sh");
  northSessionEnd = pkgs.writeShellScriptBin "north-session-end" (builtins.readFile "${flakeRoot}/dotfiles/agents/hooks/north-session-end.sh");
  mcpRegister = pkgs.writeShellScript "claude-mcp-register" (builtins.readFile "${flakeRoot}/scripts/claude-mcp-register.sh");
in
{
  options.myConfig.modules.claude.enable = lib.mkEnableOption "Claude Code CLI configuration";
  config = lib.mkIf config.myConfig.modules.claude.enable {
    environment.systemPackages = [ claudePackage northSessionEnd ];
    home-manager.users.${username} = ({ config, ... }: {
      home.file = {
        ".claude/commands".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/code/nixos-config/dotfiles/claude/commands";
        ".claude/skills".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/code/nixos-config/dotfiles/agents/skills";
        ".claude/CLAUDE.md".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/code/nixos-config/dotfiles/claude/CLAUDE.md";
        ".claude/hooks".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/code/nixos-config/dotfiles/agents/hooks";
        ".claude/agents".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/code/nixos-config/dotfiles/claude/agents";
        "code/CLAUDE.md".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/code/nixos-config/dotfiles/code/CLAUDE.md";
        ".config/caveman/config.json".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/code/nixos-config/dotfiles/caveman/config.json";
      };
      home.activation.seedClaudeSettings = config.lib.dag.entryAfter [ "writeBoundary" ] "run env INSTALL_BIN=${pkgs.coreutils}/bin/install MKDIR_BIN=${pkgs.coreutils}/bin/mkdir MV_BIN=${pkgs.coreutils}/bin/mv REALPATH_BIN=${pkgs.coreutils}/bin/realpath RM_BIN=${pkgs.coreutils}/bin/rm FLOCK_BIN=${pkgs.util-linux}/bin/flock JQ_BIN=${pkgs.jq}/bin/jq ${claudeSettingsSeeder} ${claudeSettingsSeed} $HOME/.claude/settings.json\n";
      home.activation.installCaveman = config.lib.dag.entryAfter [ "writeBoundary" "seedClaudeSettings" ] "CLAUDE=${claudePackage}/bin/claude\nWANT=37c28ebb1e0a\nGITC=$(run mktemp)\nrun ${pkgs.git}/bin/git config -f \"$GITC\" url.\"https://github.com/\".insteadOf \"git@github.com:\"\nif [ ! -e $HOME/.claude/plugins/cache/caveman ]; then\n  run timeout 90 $CLAUDE plugin marketplace add tompassarelli/caveman || true\n  run timeout 90 env GIT_CONFIG_GLOBAL=\"$GITC\" $CLAUDE plugin install caveman@caveman || true\nelif [ ! -e $HOME/.claude/plugins/cache/caveman/caveman/$WANT ]; then\n  run timeout 90 $CLAUDE plugin marketplace update caveman || true\n  run timeout 90 $CLAUDE plugin uninstall caveman@caveman || true\n  run timeout 90 env GIT_CONFIG_GLOBAL=\"$GITC\" $CLAUDE plugin install caveman@caveman || true\n  run find $HOME/.claude/plugins/cache/caveman/caveman -mindepth 1 -maxdepth 1 ! -name \"$WANT\" -exec rm -rf {} + || true\nfi\nrun rm -f \"$GITC\"\n";
      home.activation.registerMcpServers = config.lib.dag.entryAfter [ "writeBoundary" ] "if ! run env CLAUDE_BIN=${claudePackage}/bin/claude JQ_BIN=${pkgs.jq}/bin/jq TIMEOUT_BIN=${pkgs.coreutils}/bin/timeout CLAUDE_JSON=$HOME/.claude.json LIFE=$HOME/.local/state/north FRAM_MCP_BIN=${framPkg}/bin/fram-mcp NORTH_MCP_BIN=${northPkg}/bin/north-mcp WANT_NORTH_PORT=7977 ${mcpRegister}; then\n  echo \"warning: MCP server registration failed; agent-config-check --local will report the drift\" >&2\nfi\n";
    });
  };
}
