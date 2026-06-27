{ config, lib, pkgs, ... }:

{
  options.myConfig.modules.bc.enable = lib.mkEnableOption "Enable bc arbitrary-precision calculator language";
  config = lib.mkIf config.myConfig.modules.bc.enable {
    environment.systemPackages = with pkgs; [ bc ];
  };
}
