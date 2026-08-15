{ config, lib, pkgs, inputs, ... }:

{
  config = lib.mkIf config.myConfig.modules.gjoa.enable {
    environment.systemPackages = [ (inputs.gjoa.packages."${pkgs.stdenv.hostPlatform.system}").gjoa ];
    xdg.mime.defaultApplications = lib.mkIf config.myConfig.modules.gjoa.default {
      "text/html" = "gjoa.desktop";
      "x-scheme-handler/http" = "gjoa.desktop";
      "x-scheme-handler/https" = "gjoa.desktop";
      "x-scheme-handler/about" = "gjoa.desktop";
      "x-scheme-handler/unknown" = "gjoa.desktop";
    };
  };
}
