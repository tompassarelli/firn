{ config, lib, pkgs, ... }:

let
  racoPackages = [ "drracket-vim-tool" "db" ];
  racoEnsure = pkgs.writeShellScript "raco-ensure-packages" ''
    for pkg in ${lib.concatStringsSep " " racoPackages}; do
      if ! ${pkgs.unstable.racket}/bin/raco pkg show "$pkg" 2>/dev/null | grep -q "Package name:"; then
        ${pkgs.unstable.racket}/bin/raco pkg install --auto --skip-installed "$pkg"
      fi
    done

  '';
in
{
  options.myConfig.modules.drracket.enable = lib.mkEnableOption "DrRacket IDE";
  config = lib.mkIf config.myConfig.modules.drracket.enable {
    environment.systemPackages = [ pkgs.unstable.racket ];
    system.activationScripts.racoPackages.text = ''
      /run/wrappers/bin/sudo -u ${config.myConfig.modules.users.username} ${racoEnsure} || true

    '';
  };
}
