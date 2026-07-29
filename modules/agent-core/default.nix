{ config, lib, ... }:

let
  username = config.myConfig.modules.users.username;
in
{
  options.myConfig.modules.agent-core.enable = lib.mkEnableOption "Shared provider-neutral agent configuration";
  config = lib.mkIf config.myConfig.modules.agent-core.enable {
    home-manager.users.${username} = ({ config, ... }: {
      home.file = {
        ".agents/AGENTS.md".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/code/north/main/profiles/tom/AGENTS.md";
        ".agents/skills".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/code/north/main/profiles/tom/skills";
        ".agents/docs".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/code/north/main/profiles/tom/docs";
        ".agents/hooks".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/code/north/main/profiles/tom/hooks";
        "code/AGENTS.md".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/code/nixos-config/dotfiles/code/AGENTS.md";
      };
    });
  };
}
