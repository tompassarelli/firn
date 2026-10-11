{ config, lib, pkgs, ... }:

{
  config = lib.mkIf config.myConfig.modules.sbcl.enable {
    "environment" = {
      "systemPackages" = [ pkgs.sbcl ];
    };
  };
  options."myConfig"."modules"."sbcl"."enable" = lib.mkEnableOption "Steel Bank Common Lisp compiler";
}
