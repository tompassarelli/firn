{ config, lib, ... }:

let
  username = config.myConfig.modules.users.username;
in
{
  options.myConfig.modules.agent-core.enable = lib.mkEnableOption "Shared provider-neutral agent configuration";
  config = lib.mkIf config.myConfig.modules.agent-core.enable {
    home-manager.users.${username} = ({ config, ... }: {
      home.file = {
        ".agents/AGENTS.md".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/code/nixos-config/dotfiles/agents/AGENTS.md";
        ".agents/skills".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/code/nixos-config/dotfiles/agents/skills";
        ".agents/docs".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/code/nixos-config/dotfiles/agents/docs";
        ".agents/hooks".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/code/nixos-config/dotfiles/agents/hooks";
        "code/AGENTS.md".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/code/nixos-config/dotfiles/code/AGENTS.md";
      };
    });
  };
}
