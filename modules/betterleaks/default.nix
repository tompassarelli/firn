{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.betterleaks;
in
{
  options.myConfig.modules.betterleaks.enable =
    lib.mkEnableOption "Enable betterleaks secret scanner (safe-push depends on it being on PATH)";
  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      pkgs.betterleaks
      pkgs.gitleaks
    ];
  };
}
