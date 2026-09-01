{ config, lib, pkgs, flakeRoot, ... }:

((username: ((homeDir: ((agentGeneration: ((providerAdapter: {
  options.myConfig.modules.codex.enable = lib.mkEnableOption "OpenAI Codex CLI (exact North managed runtime)";
  config = lib.mkIf config.myConfig.modules.codex.enable {
    environment.etc = {
      "codex/requirements.toml".source = "${flakeRoot}/modules/codex/requirements.toml";
      "codex/hooks/runtime/bash" = {
        source = "${pkgs.bash}/bin/bash";
      };
      "codex/hooks/runtime/cat" = {
        source = "${pkgs.coreutils}/bin/cat";
      };
      "codex/hooks/runtime/env" = {
        source = "${pkgs.coreutils}/bin/env";
      };
      "codex/hooks/runtime/git" = {
        source = "${pkgs.git}/bin/git";
      };
      "codex/hooks/runtime/mktemp" = {
        source = "${pkgs.coreutils}/bin/mktemp";
      };
      "codex/hooks/runtime/python3" = {
        source = "${pkgs.python3}/bin/python3";
      };
      "codex/hooks/runtime/rm" = {
        source = "${pkgs.coreutils}/bin/rm";
      };
      "codex/hooks/runtime/timeout" = {
        source = "${pkgs.coreutils}/bin/timeout";
      };
    };
    systemd.tmpfiles.rules = [
      "d /etc/codex/hooks/lib 0755 root root -"
      (providerAdapter "lib/north-agent-activation.sh")
      (providerAdapter "beagle-session-start.sh")
      (providerAdapter "firn-system-policy")
      (providerAdapter "concrete-model-identity-guard.sh")
      (providerAdapter "launch-critical-worktree-guard.sh")
      (providerAdapter "lib/launch_critical_decide.py")
      (providerAdapter "lib/launch_critical_paths.py")
      (providerAdapter "tripwire-guard.sh")
      (providerAdapter "corpus-scan-guard.sh")
      (providerAdapter "resource-safe-search-guard.sh")
      (providerAdapter "session-kill-guard.sh")
      (providerAdapter "lib/authoring-killswitch.sh")
    ];
    home-manager.users.${username} = ({ config, ... }: {
      home.file = {
        ".codex/AGENTS.md".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.local/state/north/agents/current/instructions/codex/AGENTS.md";
        ".codex/config.toml".source = "${flakeRoot}/dotfiles/codex/config.toml";
        ".codex/prompts".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/code/nixos-config/dotfiles/codex/prompts";
      };
    });
  };
}) (adapterId: "L+ /etc/codex/hooks/${adapterId} - - - - ${agentGeneration}/provider-hooks/${adapterId}"))) "${homeDir}/.local/state/north/agents/current")) config.myConfig.modules.users.homeDir)) config.myConfig.modules.users.username)
