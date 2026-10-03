{ config, flakeRoot, lib, pkgs, ... }:

((liveInputs: ((devCommandNames: ((mkDev: ((devCommands: {
  options.myConfig.modules.beagle.enable = lib.mkEnableOption "Beagle checkout development commands";
  config = lib.mkIf config.myConfig.modules.beagle.enable {
    environment.systemPackages = devCommands;
  };
}) (builtins.map mkDev devCommandNames))) (name: pkgs.writeShellApplication {
    name = "${name}-dev";
    runtimeInputs = liveInputs;
    text = ''
      checkout=''${BEAGLE_CHECKOUT:-$HOME/code/beagle/main}
      target=$checkout/bin/${name}
      if [ ! -x "$target" ]; then
        echo "${name}-dev: checkout executable missing: $target" >&2
        exit 127
      fi
      echo "${name}-dev: provenance=checkout path=$target" >&2
      exec "$target" "$@"
    '';
  }))) [
    "beagle"
    "beagle-build"
    "beagle-check"
    "beagle-validate"
    "beagle-syntax"
    "beagle-fix"
    "beagle-repair"
    "beagle-doctor"
    "beagle-daemon"
    "beagle-lsp"
  ])) (with pkgs; [
    bash
    coreutils
    direnv
    findutils
    gawk
    git
    gnugrep
    gnused
  ]))
