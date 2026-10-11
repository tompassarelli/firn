{ config, lib, pkgs, ... }:

{
  config = lib.mkIf config.myConfig.modules.drracket.enable {
    "environment" = {
      "systemPackages" = [ pkgs.unstable.racket ];
    };
    "system" = {
      "activationScripts" = {
        "racoPackages" = {
          "text" = (((("/run/wrappers/bin/sudo -u " + config.myConfig.modules.users.username) + " ") + builtins.toString (pkgs.writeShellScript "raco-ensure-packages" (((("for pkg in drracket-vim-tool; do\n  if ! " + builtins.toString pkgs.unstable.racket) + "/bin/raco pkg show \"$pkg\" 2>/dev/null | grep -qE \"^[[:space:]]+$pkg[*[:space:]]\"; then\n    ") + builtins.toString pkgs.unstable.racket) + "/bin/raco pkg install --auto --skip-installed \"$pkg\"\n  fi\ndone\n\n"))) + " || true\n\n");
        };
      };
    };
  };
  options."myConfig"."modules"."drracket"."enable" = lib.mkEnableOption "DrRacket IDE";
}
