{ config, lib, pkgs, ... }:

{
  options.myConfig.modules.zen-browser.default = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = "Set Zen Browser as the default browser via MIME types";
  };
  imports = [ ./zen-browser.nix ];
  options.myConfig.modules.zen-browser.enable = lib.mkEnableOption "zen-browser";
}
