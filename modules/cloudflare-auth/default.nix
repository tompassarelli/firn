{ config, lib, ... }:

{
  config = lib.mkIf config.myConfig.modules.cloudflare-auth.enable {
    "sops" = {
      "secrets" = {
        "cloudflare-global-api-key" = {
          "owner" = config.myConfig.modules.users.username;
          "sopsFile" = config.myConfig.modules.cloudflare-auth.sopsFile;
        };
      };
    };
  };
  options."myConfig"."modules"."cloudflare-auth"."enable" = lib.mkEnableOption "Cloudflare deployment credentials";
  options."myConfig"."modules"."cloudflare-auth"."sopsFile" = lib.mkOption {
    type = lib.types.str;
    description = "sops file holding Cloudflare deployment credentials";
  };
}
