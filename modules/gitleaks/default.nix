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
  options.myConfig.modules.gitleaks.enable =
    lib.mkEnableOption "Enable gitleaks secret scanner (safe-push depends on it being on PATH)";
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.gitleaks ]; };
}
