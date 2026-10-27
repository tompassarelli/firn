{
  config,
  lib,
  pkgs,
  flakeRoot,
  ...
}:

let
  cfg = config.myConfig.modules.codex;
  username = config.myConfig.modules.users.username;
  homeDir = config.myConfig.modules.users.homeDir;
  codexConfigFile = cfg.configFile;
  context = builtins.fromJSON (builtins.readFile ../north-profile/context.json);
  contextWindow =
    if (context.window < context.modelMaxContextWindow) then
      context.window
    else
      context.modelMaxContextWindow;
  renderedCodexConfigFile = pkgs.writeText "config.toml" (
    ''
      model_context_window = ${builtins.toString contextWindow}
      model_auto_compact_token_limit = ${builtins.toString context.autoCompactTokenLimit}
    ''
    + builtins.readFile codexConfigFile
  );
  agentGeneration = "${homeDir}/.local/state/north/agents/current";
  providerAdapter =
    adapterId:
    "L+ /etc/codex/hooks/${adapterId} - - - - ${agentGeneration}/provider-hooks/${adapterId}";
in
{
  options.myConfig.modules.codex = {
    enable = lib.mkEnableOption "OpenAI Codex CLI (exact North managed runtime)";
    configFile = lib.mkOption {
      type = lib.types.path;
      default = builtins.path {
        path = "${flakeRoot}/dotfiles/codex/config.toml";
        name = "config.toml";
      };
      description = "Codex config.toml linked at ~/.codex/config.toml";
    };
  };
  config = lib.mkIf cfg.enable {
    environment.etc = {
      "codex/requirements.toml".source = builtins.path {
        path = "${flakeRoot}/modules/codex/requirements.toml";
        name = "requirements.toml";
      };
      "codex/hooks/runtime/bash".source = "${pkgs.bash}/bin/bash";
      "codex/hooks/runtime/cat".source = "${pkgs.coreutils}/bin/cat";
      "codex/hooks/runtime/env".source = "${pkgs.coreutils}/bin/env";
      "codex/hooks/runtime/git".source = "${pkgs.git}/bin/git";
      "codex/hooks/runtime/mktemp".source = "${pkgs.coreutils}/bin/mktemp";
      "codex/hooks/runtime/python3".source = "${pkgs.python3}/bin/python3";
      "codex/hooks/runtime/rm".source = "${pkgs.coreutils}/bin/rm";
      "codex/hooks/runtime/timeout".source = "${pkgs.coreutils}/bin/timeout";
    };
    systemd.tmpfiles.rules = [
      "d /etc/codex/hooks/lib 0755 root root -"
      (providerAdapter "north-hook.sh")
      (providerAdapter "lib/north-agent-activation.sh")
      (providerAdapter "firn-system-policy")
      (providerAdapter "concrete-model-identity-guard.sh")
      (providerAdapter "lib/launch_critical_decide.py")
      (providerAdapter "corpus-scan-guard.sh")
      (providerAdapter "native-item-guard.sh")
      (providerAdapter "clipboard-guard.sh")
      (providerAdapter "generated-policy-guard.sh")
      (providerAdapter "language-guard.sh")
      (providerAdapter "resource-safe-search-guard.sh")
      (providerAdapter "modern-search-guard.sh")
      (providerAdapter "worker-tier-guard.sh")
      (providerAdapter "session-kill-guard.sh")
      (providerAdapter "lib/authoring-killswitch.sh")
      (providerAdapter "codex-behavior-guard.sh")
      (providerAdapter "lib/codex_behavior.py")
      (providerAdapter "lib/spawn_capacity.py")
      (providerAdapter "lib/shellcmd.py")
      (providerAdapter "lib/defaults.toml")
      (providerAdapter "lib/laptop_line.py")
      (providerAdapter "lib/defaults.py")
      (providerAdapter "defaults.toml")
    ];
    home-manager.users.${username} = { config, ... }: {
      home.file = {
        ".codex/AGENTS.md".source =
          config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.local/state/north/agents/current/instructions/codex/AGENTS.md";
        ".codex/config.toml".source = renderedCodexConfigFile;
        ".codex/prompts".source =
          config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/code/north/main/harness/codex/prompts";
        ".local/bin/codex".source =
          config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.local/lib/codex/current/bin/codex";
      };
    };
  };
}
