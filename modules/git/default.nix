{ config, lib, pkgs, ... }:

let
  username = config.myConfig.modules.users.username;
  email = config.myConfig.modules.users.email;
  fullName = config.myConfig.modules.users.fullName;
in
{
  options.myConfig.modules.git.enable = lib.mkEnableOption "Git configuration";
  config = lib.mkIf config.myConfig.modules.git.enable {
    home-manager.users.${username} = ({ config, ... }: {
      programs.git = {
        enable = true;
        settings = {
          user.name = fullName;
          user.email = email;
          init.defaultBranch = "main";
          core.editor = "nvim";
          merge.conflictstyle = "diff3";
          diff.colorMoved = "default";
        };
      };
      programs.delta = {
        enable = true;
        enableGitIntegration = true;
        options = {
          navigate = true;
        };
      };
    });
  };
}
