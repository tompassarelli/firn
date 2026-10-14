{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.yq-go;
in
{
  options.myConfig.modules.yq-go.enable = lib.mkEnableOption "yq YAML/JSON/TOML processor";
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.yq-go ]; };
}
