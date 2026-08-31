{ config, lib, pkgs, ... }:

((version: ((babashka: {
  options.myConfig.modules.babashka.enable = lib.mkEnableOption "Babashka native Clojure scripting";
  config = lib.mkIf config.myConfig.modules.babashka.enable {
    environment.systemPackages = [ babashka ];
  };
}) (pkgs.stdenvNoCC.mkDerivation {
    pname = "babashka";
    version = version;
    src = pkgs.fetchurl {
      url = "https://github.com/babashka/babashka/releases/download/v${version}/babashka-${version}-linux-amd64-static.tar.gz";
      hash = "sha256-6z7dEoJ28Lb73vyxjcfUJlKpXqQJqBs08I42uKw8vDw=";
    };
    sourceRoot = ".";
    dontBuild = true;
    installPhase = ''
      runHook preInstall
      install -Dm755 bb "$out/bin/bb"
      runHook postInstall
    '';
    doInstallCheck = true;
    installCheckPhase = ''
      test "$("$out/bin/bb" --version)" = "babashka v${version}"
    '';
    meta = pkgs.babashka.meta;
  }))) "1.13.220")
