{ config, lib, ... }:

{
  config = lib.mkIf config.myConfig.modules.nix-ld.enable {
    "programs" = {
      "nix-ld" = {
        "enable" = true;
      };
    };
  };
  options."myConfig"."modules"."nix-ld"."enable" = lib.mkEnableOption "nix-ld dynamic library shim";
}
