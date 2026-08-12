{ config, lib, pkgs, ... }:

{
  options.myConfig.modules.clojure.enable = lib.mkEnableOption "Clojure tooling — LSP, linting, formatting (native binaries, no JVM)";
  config = lib.mkIf config.myConfig.modules.clojure.enable {
    environment.systemPackages = with pkgs.unstable; [ clj-kondo clojure-lsp jet cljfmt ];
  };
}
