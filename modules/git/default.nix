{ config, lib, ... }:
let
  cfg = config.myConfig.modules.git;
in
{
  options.myConfig.modules.git.enable = lib.mkEnableOption "Git configuration";
  config = lib.mkIf cfg.enable {
    home-manager.users.${config.myConfig.modules.users.username} = _hm: {
      programs = {
        delta = {
          enable = true;
          enableGitIntegration = true;
          options.navigate = true;
        };
        git = {
          enable = true;
          settings = {
            core.editor = "nvim";
            diff.colorMoved = "default";
            gc = {
              auto = 0;
              autoDetach = false;
            };
            init.defaultBranch = "main";
            maintenance = {
              auto = false;
              autoDetach = false;
            };
            merge.conflictstyle = "diff3";
            user = {
              email = config.myConfig.modules.users.email;
              name = config.myConfig.modules.users.fullName;
            };
          };
        };
      };
    };
  };
}
