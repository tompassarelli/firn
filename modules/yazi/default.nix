{ config, lib, ... }:
let
  cfg = config.myConfig.modules.yazi;
in
{
  config = lib.mkIf cfg.enable {
    home-manager.users.${config.myConfig.modules.users.username}.programs.yazi = {
      enable = true;
      settings.opener.edit = [
        {
          block = true;
          for = "unix";
          run = "nvim \"$@\"";
        }
      ];
      shellWrapperName = "yy";
    };
  };
  options.myConfig.modules.yazi.enable = lib.mkEnableOption "Yazi file manager";
}
