{ config, lib, pkgs, flakeRoot, ... }:

((username: ((homeDir: ((northPkg: ((codexExpectedIdentity: ((codexUpstreamPkg: ((codexObservedIdentity: ((codexPkg: ((enforcement: ((agentGeneration: ((promoted: ((providerAdapter: {
  options.myConfig.modules.codex.enable = lib.mkEnableOption "OpenAI Codex CLI (exact North managed runtime)";
  config = lib.mkIf config.myConfig.modules.codex.enable {
    environment.systemPackages = [ codexPkg ];
    environment.etc = {
      "codex/requirements.toml".source = "${flakeRoot}/modules/codex/requirements.toml";
      "codex/runtime" = {
        source = codexPkg;
      };
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
      "codex/hooks/runtime/node" = {
        source = "${pkgs.nodejs}/bin/node";
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
      (promoted "agent-spawn-guard.sh" "north/profiles/tom/hooks/agent-spawn-guard.sh")
      (promoted "launch-critical-worktree-guard.sh" "north/profiles/tom/hooks/launch-critical-worktree-guard.sh")
      (promoted "lib/launch_critical_decide.py" "north/profiles/tom/hooks/lib/launch_critical_decide.py")
      (promoted "lib/launch_critical_paths.py" "north/profiles/tom/hooks/lib/launch_critical_paths.py")
      (promoted "tripwire-guard.sh" "north/profiles/tom/hooks/tripwire-guard.sh")
      (promoted "corpus-scan-guard.sh" "north/profiles/tom/hooks/corpus-scan-guard.sh")
      (promoted "session-kill-guard.sh" "north/profiles/tom/hooks/session-kill-guard.sh")
      (promoted "logcompress-hook.js" "north/profiles/tom/hooks/logcompress-hook.js")
      (promoted "logcompress.js" "north/profiles/tom/hooks/logcompress.js")
      (promoted "lib/authoring-killswitch.sh" "north/profiles/tom/hooks/lib/authoring-killswitch.sh")
      (promoted "lib/harness-dial.sh" "north/profiles/tom/hooks/lib/harness-dial.sh")
    ];
    home-manager.users.${username} = ({ config, ... }: {
      home.file = {
        ".codex/AGENTS.md".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.local/state/north/agents/current/instructions/codex/AGENTS.md";
        ".codex/config.toml".source = "${flakeRoot}/dotfiles/codex/config.toml";
        ".codex/prompts".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/code/nixos-config/dotfiles/codex/prompts";
      };
    });
  };
}) (adapterId: "L+ /etc/codex/hooks/${adapterId} - - - - ${agentGeneration}/provider-hooks/${adapterId}"))) (relative: source: "L+ /etc/codex/hooks/${relative} - - - - ${enforcement}/${source}"))) "${homeDir}/.local/state/north/agents/current")) "/var/lib/north-enforcement/active/current")) (lib.throwIfNot (codexObservedIdentity == codexExpectedIdentity) "codex: managed runtime identity drifted; expected ${builtins.toJSON codexExpectedIdentity}; observed ${builtins.toJSON codexObservedIdentity}" codexUpstreamPkg))) {
    version = codexUpstreamPkg.version or null;
    owner = codexUpstreamPkg.src.owner or null;
    repo = codexUpstreamPkg.src.repo or null;
    rev = codexUpstreamPkg.src.rev or null;
    tag = codexUpstreamPkg.src.tag or null;
    srcHash = codexUpstreamPkg.src.outputHash or null;
    cargoHash = codexUpstreamPkg.cargoHash or null;
  })) pkgs.master.codex)) {
    version = "0.149.0";
    owner = "openai";
    repo = "codex";
    rev = "refs/tags/rust-v0.149.0";
    tag = "rust-v0.149.0";
    srcHash = "sha256-SMVTW/CcGz4xxyeFe3KUf3Ns6jp+2SRMTvtA2o2+y7Q=";
    cargoHash = "sha256-K58PL588Hhk75FyXgU6b8IEAco8FIz8oGd1S0WgOjyQ=";
  })) "${homeDir}/code/north/main")) config.myConfig.modules.users.homeDir)) config.myConfig.modules.users.username)
