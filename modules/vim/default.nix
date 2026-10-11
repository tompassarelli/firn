{ config, lib, pkgs, ... }:

{
  config = lib.mkIf config.myConfig.modules.vim.enable {
    "environment" = {
      "systemPackages" = [ pkgs.vim ];
    };
  };
  options."myConfig"."modules"."vim"."enable" = lib.mkEnableOption "Vim text editor";
}
