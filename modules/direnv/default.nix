{ config, lib, ... }:
let
  cfg = config.myConfig.modules.direnv;
in
{
  options.myConfig.modules.direnv.enable =
    lib.mkEnableOption "direnv for automatic dev shell activation";
  config = lib.mkIf cfg.enable {
    home-manager.users.${config.myConfig.modules.users.username}.programs.direnv = {
      enable = true;
      nix-direnv.enable = true;
    };
    programs.direnv = {
      enable = true;
      nix-direnv.enable = true;
    };
  };
}
