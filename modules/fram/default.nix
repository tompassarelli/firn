{ config, lib, pkgs, inputs, ... }:

{
  options.myConfig.modules.fram.enable = lib.mkEnableOption "fram claim-engine CLI suite";
  config = lib.mkIf config.myConfig.modules.fram.enable {
    environment.systemPackages = [ inputs.fram.packages."${pkgs.stdenv.hostPlatform.system}".default ];
  };
}
