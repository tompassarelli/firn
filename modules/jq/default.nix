{ config, lib, pkgs, ... }:

{
  options.myConfig.modules.jq.enable = lib.mkEnableOption "jq command-line JSON processor";
  config = lib.mkIf config.myConfig.modules.jq.enable {
    environment.systemPackages = with pkgs; [ jq ];
  };
}
