{ config, lib, pkgs, ... }:

let
  username = config.myConfig.modules.users.username;
in
{
  options.myConfig.modules.opencode.enable = lib.mkEnableOption "opencode — open-source, model-agnostic terminal coding agent";
  config = lib.mkIf config.myConfig.modules.opencode.enable {
    environment.systemPackages = [ pkgs.opencode ];
    home-manager.users.${username} = ({ config, ... }: {
      home.file.".config/opencode/opencode.json".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/code/nixos-config/dotfiles/opencode/opencode.json";
    });
  };
}
