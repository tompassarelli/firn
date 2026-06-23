{ config, lib, flakeRoot, ... }:

let
  username = config.myConfig.modules.users.username;
  sopsFile = config.myConfig.modules.clockify.sopsFile;
in
{
  options.myConfig.modules.clockify.enable = lib.mkEnableOption "clockify";
  options.myConfig.modules.clockify.sopsFile = lib.mkOption {
    type = lib.types.str;
    default = "${flakeRoot}/secrets/clockify.yaml";
    description = "sops file holding the Clockify API key (msa-clockify-api-key)";
  };
  config = lib.mkIf config.myConfig.modules.clockify.enable {
    sops.secrets."msa-clockify-api-key" = {
      sopsFile = sopsFile;
      owner = username;
    };
  };
}
