{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.python;
in
{
  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      (pkgs.python3.withPackages (pythonPackages: [ pythonPackages.boto3 ]))
    ];
  };
  options.myConfig.modules.python.enable = lib.mkEnableOption "Python runtime with uv";
}
