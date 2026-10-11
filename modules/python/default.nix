{ config, lib, pkgs, ... }:

{
  config = lib.mkIf config.myConfig.modules.python.enable {
    "environment" = {
      "systemPackages" = [
        (pkgs.python3.withPackages (__clause_argument_0: [ __clause_argument_0.boto3 ]))
      ];
    };
  };
  options."myConfig"."modules"."python"."enable" = lib.mkEnableOption "Python runtime with uv";
}
