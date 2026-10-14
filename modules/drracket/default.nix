{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.drracket;
  ensurePackages = pkgs.writeShellScript "raco-ensure-packages" ''
    for pkg in drracket-vim-tool; do
      if ! ${builtins.toString pkgs.unstable.racket}/bin/raco pkg show "$pkg" 2>/dev/null | grep -qE "^[[:space:]]+$pkg[*[:space:]]"; then
        ${builtins.toString pkgs.unstable.racket}/bin/raco pkg install --auto --skip-installed "$pkg"
      fi
    done

  '';
in
{
  options.myConfig.modules.drracket.enable = lib.mkEnableOption "DrRacket IDE";
  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ pkgs.unstable.racket ];
    system.activationScripts.racoPackages.text = ''
      /run/wrappers/bin/sudo -u ${config.myConfig.modules.users.username} ${builtins.toString ensurePackages} || true

    '';
  };
}
