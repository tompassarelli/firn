{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.gitleaks;
in
{
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.gitleaks ]; };
  options.myConfig.modules.gitleaks.enable =
    lib.mkEnableOption "Enable gitleaks secret scanner (safe-push depends on it being on PATH)";
}
