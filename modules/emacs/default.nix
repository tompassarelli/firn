{ config, lib, pkgs, ... }:

{
  config = lib.mkIf config.myConfig.modules.emacs.enable {
    "environment" = {
      "systemPackages" = [ pkgs.emacs-pgtk ];
    };
  };
  options."myConfig"."modules"."emacs"."enable" = lib.mkEnableOption "GNU Emacs editor";
}
