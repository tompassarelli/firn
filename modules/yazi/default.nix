{ config, lib, pkgs, ... }:

let
  username = config.myConfig.modules.users.username;
in
{
  options.myConfig.modules.yazi.enable = lib.mkEnableOption "Yazi file manager";
  config = lib.mkIf config.myConfig.modules.yazi.enable {
    home-manager.users.${username} = ({ config, ... }: {
      programs.yazi = {
        enable = true;
        shellWrapperName = "yy";
        settings = {
          opener = {
            edit = [
              {
                run = "nvim \"$@\"";
                block = true;
                for = "unix";
              }
            ];
          };
        };
      };
    });
  };
}
