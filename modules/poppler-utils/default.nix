{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.poppler-utils;
in
{
  options.myConfig.modules.poppler-utils.enable =
    lib.mkEnableOption "Poppler PDF rendering and text extraction tools";
  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [ poppler-utils ];
  };
}
