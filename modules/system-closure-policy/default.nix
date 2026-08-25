{ config, lib, ... }:

((forbiddenExact: ((forbiddenPrefixes: ((packageId: ((forbidden_p: ((forbiddenPackages: ((forbiddenIds: {
  assertions = [
    {
      assertion = (forbiddenPackages == [ ]);
      message = "system closure policy: high-churn authoring packages must use live out-of-store entrypoints; forbidden environment.systemPackages: ${lib.concatStringsSep ", " forbiddenIds}";
    }
  ];
}) (lib.unique (builtins.map packageId forbiddenPackages)))) (builtins.filter forbidden_p config.environment.systemPackages))) (package: ((id: ((builtins.elem id forbiddenExact) || (builtins.any (prefix: ((id == prefix) || (lib.hasPrefix "${prefix}-" id))) forbiddenPrefixes) || ((builtins.match "python3-[0-9.]+-env" id) != null))) (packageId package))))) (package: lib.toLower (package.pname or package.name or "")))) [ "beagle" "fram" "north" ])) [
    "babashka"
    "bun"
    "cargo"
    "clippy"
    "clj-kondo"
    "cljfmt"
    "clojure"
    "clojure-lsp"
    "codex"
    "devenv"
    "firn"
    "firn-compiler"
    "firn-launchers"
    "firn-native"
    "framework-tool"
    "gcc-wrapper"
    "jet"
    "nodejs"
    "opencode"
    "racket"
    "rust-analyzer"
    "rustc"
    "rustfmt"
  ])
