{ config, lib, ... }:
let
  cfg = config.myConfig.modules.bunfig;
in
{
  config = lib.mkIf cfg.enable {
    home-manager.users.${config.myConfig.modules.users.username} = hm: {
      home.file.".bunfig.toml".source =
        hm.config.lib.file.mkOutOfStoreSymlink "${hm.config.home.homeDirectory}/code/nixos-config/dotfiles/bun/bunfig.toml";
    };
  };
  options.myConfig.modules.bunfig.enable =
    lib.mkEnableOption "Global Bun settings: 7-day release cooldown, no auto-install";
}
