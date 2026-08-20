{ config, lib, pkgs, flakeRoot, ... }:

((username: ((homeDir: ((northPkg: ((codexExpectedIdentity: ((codexUpstreamPkg: ((codexObservedIdentity: ((codexPkg: ((enforcement: ((promoted: {
  options.myConfig.modules.codex.enable = lib.mkEnableOption "OpenAI Codex CLI (exact North managed runtime)";
  config = lib.mkIf config.myConfig.modules.codex.enable {
    environment.systemPackages = [ codexPkg ];
    environment.etc = {
      "codex/requirements.toml".source = "${flakeRoot}/modules/codex/requirements.toml";
      "codex/runtime" = {
        source = codexPkg;
      };
      "codex/hooks/north-on-spawn-codex" = {
        source = "${flakeRoot}/dotfiles/codex/hooks/north-on-spawn-codex";
      };
      "codex/hooks/north-on-tooluse-codex" = {
        source = "${flakeRoot}/dotfiles/codex/hooks/north-on-tooluse-codex";
      };
      "codex/hooks/north-mark-delegated-codex" = {
        source = "${flakeRoot}/dotfiles/codex/hooks/north-mark-delegated-codex";
      };
      "codex/hooks/north-on-stop-codex" = {
        source = "${flakeRoot}/dotfiles/codex/hooks/north-on-stop-codex";
      };
      "codex/hooks/north-clock-guard-codex" = {
        source = "${flakeRoot}/dotfiles/codex/hooks/north-clock-guard-codex";
      };
      "codex/hooks/lib/switchboard-activity.sh".source = "${flakeRoot}/dotfiles/agents/lib/switchboard-activity.sh";
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
      (promoted "agent-spawn-guard.sh" "north/profiles/tom/hooks/agent-spawn-guard.sh")
      (promoted "launch-critical-worktree-guard.sh" "north/profiles/tom/hooks/launch-critical-worktree-guard.sh")
      (promoted "lib/launch_critical_decide.py" "north/profiles/tom/hooks/lib/launch_critical_decide.py")
      (promoted "lib/launch_critical_paths.py" "north/profiles/tom/hooks/lib/launch_critical_paths.py")
      (promoted "tripwire-guard.sh" "north/profiles/tom/hooks/tripwire-guard.sh")
      (promoted "corpus-scan-guard.sh" "north/profiles/tom/hooks/corpus-scan-guard.sh")
      (promoted "session-kill-guard.sh" "north/profiles/tom/hooks/session-kill-guard.sh")
      (promoted "logcompress-hook.js" "north/profiles/tom/hooks/logcompress-hook.js")
      (promoted "logcompress.js" "north/profiles/tom/hooks/logcompress.js")
      (promoted "registry.tsv" "north/profiles/tom/hooks/registry.tsv")
      (promoted "lib/authoring-killswitch.sh" "north/profiles/tom/hooks/lib/authoring-killswitch.sh")
      (promoted "lib/harness-dial.sh" "north/profiles/tom/hooks/lib/harness-dial.sh")
      (promoted "beagle-session-start.sh" "beagle/integrations/north/hooks/beagle-session-start.sh")
    ];
    home-manager.users.${username} = ({ config, ... }: {
      home.file = {
        ".codex/AGENTS.md".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.config/agents/AGENTS.md";
        ".codex/config.toml".source = "${flakeRoot}/dotfiles/codex/config.toml";
        ".codex/prompts".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/code/nixos-config/dotfiles/claude/commands";
      };
    });
  };
}) (relative: source: "L+ /etc/codex/hooks/${relative} - - - - ${enforcement}/${source}"))) "/var/lib/north-enforcement/active/current")) (lib.throwIfNot (codexObservedIdentity == codexExpectedIdentity) "codex: managed runtime identity drifted; expected ${builtins.toJSON codexExpectedIdentity}; observed ${builtins.toJSON codexObservedIdentity}" codexUpstreamPkg))) {
    version = codexUpstreamPkg.version or null;
    owner = codexUpstreamPkg.src.owner or null;
    repo = codexUpstreamPkg.src.repo or null;
    rev = codexUpstreamPkg.src.rev or null;
    tag = codexUpstreamPkg.src.tag or null;
    srcHash = codexUpstreamPkg.src.outputHash or null;
    cargoHash = codexUpstreamPkg.cargoHash or null;
  })) pkgs.master.codex)) {
    version = "0.146.0";
    owner = "openai";
    repo = "codex";
    rev = "refs/tags/rust-v0.146.0";
    tag = "rust-v0.146.0";
    srcHash = "sha256-/kTIOX/klxm1nq2bJsBqS8f1jZZp2ilaTeULQFPJgDk=";
    cargoHash = "sha256-N9jbH/cgAyu2QxneSnpkdaF0MgV3ZtDmN9q6rr9u+hE=";
  })) "${homeDir}/code/north/main")) config.myConfig.modules.users.homeDir)) config.myConfig.modules.users.username)
