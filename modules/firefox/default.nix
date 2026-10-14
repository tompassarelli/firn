{ lib, ... }:

{
  options.myConfig.modules.firefox = {
    default = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Set Firefox as the default browser via MIME types";
    };
    enable = lib.mkEnableOption "firefox";
  };
  imports = [ ./firefox.nix ];
}
