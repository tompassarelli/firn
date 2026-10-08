{ config, lib, pkgs, ... }:

{
  options.myConfig.modules.poppler-utils.enable = lib.mkEnableOption "Poppler PDF rendering and text extraction tools";
  config = lib.mkIf config.myConfig.modules.poppler-utils.enable {
    environment.systemPackages = with pkgs; [ poppler-utils ];
  };
}
