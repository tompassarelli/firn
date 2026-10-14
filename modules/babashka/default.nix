{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.babashka;
in
{
  options.myConfig.modules.babashka.enable = lib.mkEnableOption "Babashka native Clojure scripting";
  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      (pkgs.stdenvNoCC.mkDerivation {
        doInstallCheck = true;
        dontBuild = true;
        installCheckPhase = ''
          test "$("$out/bin/bb" --version)" = "babashka v1.13.220"
        '';
        installPhase = ''
          runHook preInstall
          install -Dm755 bb "$out/bin/bb"
          runHook postInstall
        '';
        meta = pkgs.babashka.meta;
        pname = "babashka";
        sourceRoot = ".";
        src = pkgs.fetchurl {
          hash = "sha256-6z7dEoJ28Lb73vyxjcfUJlKpXqQJqBs08I42uKw8vDw=";
          url = "https://github.com/babashka/babashka/releases/download/v1.13.220/babashka-1.13.220-linux-amd64-static.tar.gz";
        };
        version = "1.13.220";
      })
    ];
  };
}
