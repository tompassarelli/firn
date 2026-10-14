{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.curl;
in
{
  options.myConfig.modules.curl.enable = lib.mkEnableOption "curl HTTP client";
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.curl ]; };
}
