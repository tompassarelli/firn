{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.tealdeer;
in
{
  options.myConfig.modules.tealdeer.enable = lib.mkEnableOption "tealdeer";
  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ pkgs.tealdeer ];
    home-manager.users.${config.myConfig.modules.users.username} = hm: {
      xdg.configFile."tealdeer/config.toml".source =
        hm.config.lib.file.mkOutOfStoreSymlink "${hm.config.home.homeDirectory}/code/nixos-config/dotfiles/tealdeer/config.toml";
    };
  };
}
