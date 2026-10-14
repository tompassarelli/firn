{ config, lib, ... }:
let
  cfg = config.myConfig.modules.zoxide;
in
{
  config = lib.mkIf cfg.enable {
    home-manager.users.${config.myConfig.modules.users.username}.programs = {
      bash.shellAliases.cd = "z";
      zoxide = {
        enable = true;
        enableBashIntegration = true;
      };
    };
  };
  options.myConfig.modules.zoxide.enable = lib.mkEnableOption "zoxide smart directory jumper";
}
