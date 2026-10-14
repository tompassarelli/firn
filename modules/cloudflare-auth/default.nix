{ config, lib, ... }:
let
  cfg = config.myConfig.modules.cloudflare-auth;
in
{
  options.myConfig.modules.cloudflare-auth = {
    enable = lib.mkEnableOption "Cloudflare deployment credentials";
    sopsFile = lib.mkOption {
      type = lib.types.str;
      description = "sops file holding Cloudflare deployment credentials";
    };
  };
  config = lib.mkIf cfg.enable {
    sops.secrets.cloudflare-global-api-key = {
      owner = config.myConfig.modules.users.username;
      inherit (cfg) sopsFile;
    };
  };
}
