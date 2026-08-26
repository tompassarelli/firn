{ config, lib, pkgs, flakeRoot, ... }:

((username: ((homeDir: ((northPkg: ((enforcement: ((agentGeneration: ((promoted: ((providerAdapter: {
  options.myConfig.modules.codex.enable = lib.mkEnableOption "OpenAI Codex CLI (exact North managed runtime)";
  config = lib.mkIf config.myConfig.modules.codex.enable {
    environment.systemPackages = with pkgs; [ bun ];
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
      "codex/hooks/north" = {
        source = northPkg;
      };
    };
    systemd.tmpfiles.rules = [
      "d /var/lib/north-enforcement 0755 root root -"
      "d /etc/codex/hooks/lib 0755 root root -"
      (providerAdapter "north-on-spawn-codex")
      (providerAdapter "north-on-tooluse-codex")
      (providerAdapter "north-mark-delegated-codex")
      (providerAdapter "north-on-stop-codex")
      (providerAdapter "north-on-terminal-codex")
      (providerAdapter "beagle-session-start.sh")
      (providerAdapter "lib/north-agent-activation.sh")
      (promoted "agent-spawn-guard.sh" "north/agent-runtime/hooks/agent-spawn-guard.sh")
      (promoted "launch-critical-worktree-guard.sh" "nixos-config/dotfiles/agents/hooks/launch-critical-worktree-guard.sh")
      (promoted "lib/launch_critical_decide.py" "nixos-config/dotfiles/agents/hooks/lib/launch_critical_decide.py")
      (promoted "lib/launch_critical_paths.py" "nixos-config/dotfiles/agents/hooks/lib/launch_critical_paths.py")
      (promoted "tripwire-guard.sh" "nixos-config/dotfiles/agents/hooks/tripwire-guard.sh")
      (promoted "corpus-scan-guard.sh" "nixos-config/dotfiles/agents/hooks/corpus-scan-guard.sh")
      (promoted "session-kill-guard.sh" "nixos-config/dotfiles/agents/hooks/session-kill-guard.sh")
      (promoted "logcompress-hook.py" "north/agent-runtime/hooks/logcompress-hook.py")
      (promoted "logcompress.py" "north/agent-runtime/hooks/logcompress.py")
      (promoted "lib/authoring-killswitch.sh" "north/agent-runtime/hooks/lib/authoring-killswitch.sh")
      (promoted "lib/harness-dial.sh" "north/agent-runtime/hooks/lib/harness-dial.sh")
    ];
    home-manager.users.${username} = ({ config, ... }: {
      home.file = {
        ".codex/AGENTS.md".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.local/state/north/agents/current/instructions/codex/AGENTS.md";
        ".codex/config.toml".source = "${flakeRoot}/dotfiles/codex/config.toml";
        ".codex/prompts".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/code/nixos-config/dotfiles/codex/prompts";
      };
    });
  };
}) (adapterId: "L+ /etc/codex/hooks/${adapterId} - - - - ${agentGeneration}/provider-hooks/${adapterId}"))) (relative: source: "L+ /etc/codex/hooks/${relative} - - - - ${enforcement}/${source}"))) "${homeDir}/.local/state/north/agents/current")) "/var/lib/north-enforcement/active/current")) "${homeDir}/code/north/main")) config.myConfig.modules.users.homeDir)) config.myConfig.modules.users.username)
