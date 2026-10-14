{ lib, ... }:

{
  options.myConfig.modules.zen-browser = {
    default = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Set Zen Browser as the default browser via MIME types";
    };
    enable = lib.mkEnableOption "zen-browser";
  };
  imports = [ ./zen-browser.nix ];
}
