{ config, lib, pkgs, ... }:

{
  options.myConfig.modules.python.enable = lib.mkEnableOption "Python runtime with uv";
  config = lib.mkIf config.myConfig.modules.python.enable {
    environment.systemPackages = [ (pkgs.python3.withPackages (ps: with ps; [ boto3 ])) ];
  };
}
