{ config, lib, pkgs, inputs, flakeRoot, ... }:

((username: ((homeDir: ((claudePackage: ((psBin: ((northPkg: ((claudeSettingsSeed: ((claudeSettingsSeeder: ((agentsRuntimePath: ((mcpRegister: {
  options.myConfig.modules.claude.enable = lib.mkEnableOption "Claude Code CLI configuration";
  config = lib.mkIf config.myConfig.modules.claude.enable {
    environment.systemPackages = [ claudePackage ];
    home-manager.users.${username} = ({ config, ... }: {
      home.file = {
        ".claude/commands".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/code/nixos-config/dotfiles/claude/commands";
        ".claude/skills".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.config/agents/skills";
        ".claude/CLAUDE.md".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.config/agents/CLAUDE.md";
        ".claude/hooks".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.agents/hooks";
        "code/CLAUDE.md".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.config/agents/code-CLAUDE.md";
      };
      home.activation.seedClaudeSettings = config.lib.dag.entryAfter [ "writeBoundary" ] "run ${pkgs.coreutils}/bin/env PATH=${agentsRuntimePath}:$PATH INSTALL_BIN=${pkgs.coreutils}/bin/install MKDIR_BIN=${pkgs.coreutils}/bin/mkdir MV_BIN=${pkgs.coreutils}/bin/mv REALPATH_BIN=${pkgs.coreutils}/bin/realpath RM_BIN=${pkgs.coreutils}/bin/rm FLOCK_BIN=${pkgs.util-linux}/bin/flock JQ_BIN=${pkgs.jq}/bin/jq ${claudeSettingsSeeder} ${claudeSettingsSeed} $HOME/.claude/settings.json\n";
      home.activation.registerMcpServers = config.lib.dag.entryAfter [ "writeBoundary" ] "if ! run env CLAUDE_BIN=${claudePackage}/bin/claude JQ_BIN=${pkgs.jq}/bin/jq TIMEOUT_BIN=${pkgs.coreutils}/bin/timeout CLAUDE_JSON=$HOME/.claude.json LIFE=$HOME/.local/state/north NORTH_MCP_BIN=${northPkg}/bin/north-mcp WANT_NORTH_PORT=7977 ${mcpRegister}; then\n  echo \"warning: MCP server registration failed; agent-config-check --local will report the drift\" >&2\nfi\n";
    });
  };
}) (pkgs.writeShellScript "claude-mcp-register" (builtins.readFile "${flakeRoot}/scripts/claude-mcp-register.sh")))) (lib.makeBinPath [ pkgs.bash pkgs.coreutils pkgs.findutils pkgs.gawk pkgs.python3 ]))) (pkgs.writeShellScript "claude-settings-seed" (builtins.readFile "${flakeRoot}/scripts/claude-settings-seed.sh")))) (pkgs.writeText "claude-settings.json" (builtins.readFile "${flakeRoot}/dotfiles/claude/settings.json")))) "${homeDir}/code/north/main")) (if pkgs.stdenv.hostPlatform.isDarwin then "/bin/ps" else "${pkgs.procps}/bin/ps"))) pkgs.master.claude-code)) config.myConfig.modules.users.homeDir)) config.myConfig.modules.users.username)
