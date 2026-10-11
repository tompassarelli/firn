{ config, lib, pkgs, ... }:

{
  config = lib.mkIf config.myConfig.modules.forgejo-cli.enable {
    "environment" = {
      "systemPackages" = [ pkgs.forgejo-cli ];
    };
  };
  options."myConfig"."modules"."forgejo-cli"."enable" = lib.mkEnableOption "Forgejo CLI for repo / issue / CI ops against codeberg + other Forgejo instances";
}
