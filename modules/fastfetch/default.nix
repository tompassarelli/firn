{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.fastfetch;
in
{
  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ pkgs.fastfetch ];
    home-manager.users.${config.myConfig.modules.users.username} = hm: {
      xdg.configFile."fastfetch/config.jsonc".source =
        hm.config.lib.file.mkOutOfStoreSymlink "${hm.config.home.homeDirectory}/code/nixos-config/dotfiles/fastfetch/config.jsonc";
    };
  };
  options.myConfig.modules.fastfetch.enable = lib.mkEnableOption "fastfetch";
}
