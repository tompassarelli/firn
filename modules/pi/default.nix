{
  config,
  lib,
  ...
}:
let
  cfg = config.myConfig.modules.pi;
  username = config.myConfig.modules.users.username;
in
{
  options.myConfig.modules.pi.enable =
    lib.mkEnableOption "pi terminal coding agent (MIT, earendil-works/pi releases installed by north runtime pi)";
  config = lib.mkIf cfg.enable {
    home-manager.users.${username} =
      { config, ... }:
      {
        home.file.".local/bin/pi".source =
          config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.local/lib/pi/current/bin/pi";
      };
  };
}
