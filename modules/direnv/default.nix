{ config, lib, pkgs, ... }:

((username: {
  options.myConfig.modules.direnv.enable = lib.mkEnableOption "direnv for automatic dev shell activation";
  config = lib.mkIf config.myConfig.modules.direnv.enable {
    programs.direnv = {
      enable = true;
      nix-direnv.enable = true;
    };
    home-manager.users.${username} = ({ config, ... }: {
      programs.direnv = {
        enable = true;
        nix-direnv.enable = true;
      };
    });
  };
}) config.myConfig.modules.users.username)
