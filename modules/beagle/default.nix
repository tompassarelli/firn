{ config, lib, pkgs, inputs, ... }:

let
  beaglePkg = inputs.beagle.packages."${pkgs.stdenv.hostPlatform.system}".default;
  liveInputs = with pkgs; [
    bash
    coreutils
    direnv
    findutils
    gawk
    git
    gnugrep
    gnused
  ];
  devCommandNames = [
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
  ];
  packagedCommandNames = [ "beagle" "beagle-build" "beagle-check" "beagle-daemon" "beagle-lsp" ];
  mkDev = name: pkgs.writeShellApplication {
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
  };
  mkPackaged = name: pkgs.writeShellApplication {
    name = "${name}-packaged";
    text = ''
      exec ${beaglePkg}/bin/${name} "$@"
    '';
  };
  devCommands = builtins.map mkDev devCommandNames;
  packagedCommands = builtins.map mkPackaged packagedCommandNames;
in
{
  options.myConfig.modules.beagle.enable = lib.mkEnableOption "beagle compiler + CLI suite (racket-pinned, hermetic) with explicit checkout-only development commands";
  config = lib.mkIf config.myConfig.modules.beagle.enable {
    environment.systemPackages = ([ beaglePkg ] ++ devCommands ++ packagedCommands);
  };
}
