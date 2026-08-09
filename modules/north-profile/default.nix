{ config, lib, ... }:

let
  username = config.myConfig.modules.users.username;
in
{
  options.myConfig.modules.north-profile.enable = lib.mkEnableOption "Publish North's agent profile at ~/.agents (see north:agent-profile contract)";
  config = lib.mkIf config.myConfig.modules.north-profile.enable {
    home-manager.users.${username} = ({ config, ... }: {
      home.file = {
        ".agents/AGENTS.md".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/code/north/main/agent-profile/AGENTS.md";
        ".agents/skills".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.local/state/north/skills";
        ".agents/docs".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/code/north/main/agent-profile/docs";
        ".agents/hooks".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/code/north/main/agent-profile/hooks";
        "code/AGENTS.md".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.config/agents/code-AGENTS.md";
      };
    });
  };
}
