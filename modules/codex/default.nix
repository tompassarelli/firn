{ config, inputs, lib, pkgs, flakeRoot, ... }:

let
  username = config.myConfig.modules.users.username;
  codexPkg = inputs.north.packages."${pkgs.stdenv.hostPlatform.system}".codex;
in
{
  options.myConfig.modules.codex.enable = lib.mkEnableOption "OpenAI Codex CLI (exact North managed runtime)";
  config = lib.mkIf config.myConfig.modules.codex.enable {
    environment.systemPackages = [ codexPkg ];
    environment.etc = {
      "codex/requirements.toml".source = "${flakeRoot}/modules/codex/requirements.toml";
      "codex/runtime" = {
        source = codexPkg;
      };
      "codex/hooks/beagle-session-start.sh".source = "${flakeRoot}/dotfiles/agents/hooks/beagle-session-start.sh";
      "codex/hooks/agent-spawn-guard.sh".source = "${flakeRoot}/dotfiles/agents/hooks/agent-spawn-guard.sh";
      "codex/hooks/code-upstream-guard.sh".source = "${flakeRoot}/dotfiles/agents/hooks/code-upstream-guard.sh";
      "codex/hooks/firn-guard.sh".source = "${flakeRoot}/dotfiles/agents/hooks/firn-guard.sh";
      "codex/hooks/north-clock-guard.sh".source = "${flakeRoot}/dotfiles/agents/hooks/north-clock-guard.sh";
      "codex/hooks/north-clock-guard.py".source = "${flakeRoot}/dotfiles/agents/hooks/north-clock-guard.py";
      "codex/hooks/tripwire-guard.sh".source = "${flakeRoot}/dotfiles/agents/hooks/tripwire-guard.sh";
      "codex/hooks/logcompress-hook.js".source = "${flakeRoot}/dotfiles/agents/hooks/logcompress-hook.js";
      "codex/hooks/logcompress.js".source = "${flakeRoot}/dotfiles/agents/hooks/logcompress.js";
      "codex/hooks/racket-build-guard.sh".source = "${flakeRoot}/dotfiles/agents/hooks/racket-build-guard.sh";
      "codex/hooks/lib/authoring-killswitch.sh".source = "${flakeRoot}/dotfiles/agents/hooks/lib/authoring-killswitch.sh";
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
        source = inputs.north;
      };
    };
    home-manager.users.${username} = ({ config, ... }: {
      home.file = {
        ".codex/AGENTS.md".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/code/nixos-config/dotfiles/agents/AGENTS.md";
        ".codex/config.toml".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/code/nixos-config/dotfiles/codex/config.toml";
        ".codex/hooks.json".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/code/nixos-config/dotfiles/codex/hooks.json";
        ".codex/prompts".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/code/nixos-config/dotfiles/claude/commands";
      };
    });
  };
}
