{
  config,
  lib,
  ...
}:
let
  cfg = config.myConfig.modules.opencode;
  username = config.myConfig.modules.users.username;
in
{
  options.myConfig.modules.opencode.enable =
    lib.mkEnableOption "opencode terminal coding agent (MIT, anomalyco/opencode releases installed by north runtime opencode)";
  config = lib.mkIf cfg.enable {
    home-manager.users.${username} =
      { config, ... }:
      {
        home.file.".local/bin/opencode".source =
          config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.local/lib/opencode/current/bin/opencode";
      };
  };
}
