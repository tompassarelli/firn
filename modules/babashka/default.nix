{ config, lib, pkgs, ... }:

{
  config = lib.mkIf config.myConfig.modules.babashka.enable {
    "environment" = {
      "systemPackages" = [
        (pkgs.stdenvNoCC.mkDerivation {
          "doInstallCheck" = true;
          "dontBuild" = true;
          "installCheckPhase" = "test \"$(\"$out/bin/bb\" --version)\" = \"babashka v1.13.220\"\n";
          "installPhase" = "runHook preInstall\ninstall -Dm755 bb \"$out/bin/bb\"\nrunHook postInstall\n";
          "meta" = pkgs.babashka.meta;
          "pname" = "babashka";
          "sourceRoot" = ".";
          "src" = pkgs.fetchurl {
            "hash" = "sha256-6z7dEoJ28Lb73vyxjcfUJlKpXqQJqBs08I42uKw8vDw=";
            "url" = "https://github.com/babashka/babashka/releases/download/v1.13.220/babashka-1.13.220-linux-amd64-static.tar.gz";
          };
          "version" = "1.13.220";
        })
      ];
    };
  };
  options."myConfig"."modules"."babashka"."enable" = lib.mkEnableOption "Babashka native Clojure scripting";
}
