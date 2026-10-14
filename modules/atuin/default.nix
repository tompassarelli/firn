{ config, lib, ... }:
let
  cfg = config.myConfig.modules.atuin;
in
{
  options.myConfig.modules.atuin.enable = lib.mkEnableOption "atuin shell history sync";
  config = lib.mkIf cfg.enable {
    home-manager.users.${config.myConfig.modules.users.username}.programs.atuin = {
      enable = true;
      enableFishIntegration = true;
      settings = {
        auto_sync = true;
        search_mode = "fuzzy";
        sync_frequency = "5m";
      };
    };
  };
}
