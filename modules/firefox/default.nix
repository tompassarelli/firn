{ config, lib, pkgs, ... }:

{
  options.myConfig.modules.firefox.enable = lib.mkEnableOption "Enable Firefox browser";
  options.myConfig.modules.firefox.default = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = "Set Firefox as the default browser via MIME types";
  };
  imports = [ ./firefox.nix ];
}
