{ config, lib, pkgs, ... }:

let
  context = builtins.fromJSON (builtins.readFile ./context.json);
  contextWindow = if (context.window < context.modelMaxContextWindow) then context.window else context.modelMaxContextWindow;
  claudeProjection = builtins.toJSON (builtins.fromJSON (builtins.readFile ./claude-hooks.json) // {
    autoCompactWindow = contextWindow;
  });
in {
  config = lib.mkIf config.myConfig.modules.north-profile.enable {
    environment.etc."north/agent-context.json".text = builtins.toJSON {
      window = contextWindow;
      autoCompactTokenLimit = context.autoCompactTokenLimit;
    };
    "home-manager" = {
      "users" = {
        ${config.myConfig.modules.users.username} = hm: {
          "home" = {
            "activation" = {
              "projectNorthClaudeHooks" = (((hm.config).lib).dag).entryAfter [ "writeBoundary" ] (((((((((((((((((((("run " + builtins.toString pkgs.coreutils) + "/bin/env CHMOD_BIN=") + builtins.toString pkgs.coreutils) + "/bin/chmod FLOCK_BIN=") + builtins.toString pkgs.util-linux) + "/bin/flock JQ_BIN=") + builtins.toString pkgs.jq) + "/bin/jq MKDIR_BIN=") + builtins.toString pkgs.coreutils) + "/bin/mkdir MV_BIN=") + builtins.toString pkgs.coreutils) + "/bin/mv REALPATH_BIN=") + builtins.toString pkgs.coreutils) + "/bin/realpath RM_BIN=") + builtins.toString pkgs.coreutils) + "/bin/rm ") + builtins.toString (pkgs.writeShellScript "north-claude-hook-projector" (builtins.readFile ./claude-hook-projector.sh))) + " ") + builtins.toString (pkgs.writeText "north-claude-hooks.json" claudeProjection)) + " $HOME/.claude/settings.json\n");
            };
            "file" = {
              ".agents/AGENTS.md" = {
                "source" = (((hm.config).lib).file).mkOutOfStoreSymlink (("" + ((hm.config).home).homeDirectory) + "/.local/state/north/agents/current/instructions/shared/AGENTS.md");
              };
              ".agents/hooks" = {
                "source" = (((hm.config).lib).file).mkOutOfStoreSymlink (("" + ((hm.config).home).homeDirectory) + "/.local/state/north/agents/current/provider-hooks");
              };
              ".agents/skills" = {
                "source" = (((hm.config).lib).file).mkOutOfStoreSymlink (("" + ((hm.config).home).homeDirectory) + "/.local/state/north/agents/current/skills/shared");
              };
              "code/AGENTS.md" = {
                "source" = (((hm.config).lib).file).mkOutOfStoreSymlink (("" + ((hm.config).home).homeDirectory) + "/.local/state/north/agents/current/instructions/code/AGENTS.md");
              };
            };
          };
        };
      };
    };
  };
  options."myConfig"."modules"."north-profile"."enable" = lib.mkEnableOption "Publish shared agent surfaces at ~/.agents";
}
