{ config, lib, pkgs, ... }:

{
  config = lib.mkIf config.myConfig.modules.clojure.enable {
    "environment" = {
      "systemPackages" = [
        pkgs.unstable.clj-kondo
        pkgs.unstable.clojure-lsp
        pkgs.unstable.jet
        pkgs.unstable.cljfmt
      ];
    };
  };
  options."myConfig"."modules"."clojure"."enable" = lib.mkEnableOption "Clojure tooling — LSP, linting, formatting (native binaries, no JVM)";
}
