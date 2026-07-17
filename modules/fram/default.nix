{ config, lib, pkgs, inputs, ... }:

let
  framPkg = inputs.fram.packages."${pkgs.stdenv.hostPlatform.system}".default;
  liveInputs = ((with pkgs; [
    babashka
    clojure
    jdk
    coreutils
    bash
    gnused
    gnugrep
    git
  ]) ++ (lib.optionals pkgs.stdenv.hostPlatform.isLinux (with pkgs; [ iproute2 ])));
  commands = [ "fram" "fram-daemon" "fram-mcp" "fram-primer" "fram-up" "fram-code-author" ];
  mkLive = name: lib.hiPrio (pkgs.writeShellApplication {
    name = name;
    runtimeInputs = liveInputs;
    text = ''
      checkout=''${FRAM_CHECKOUT:-$HOME/code/fram}
      target=$checkout/bin/${name}
      if [ ! -x "$target" ]; then
        echo "${name}: live checkout executable missing: $target" >&2
        echo "${name}: restore that checkout or use ${name}-packaged for the pinned closure" >&2
        exit 127
      fi
      exec "$target" "$@"
    '';
  });
  mkPackaged = name: pkgs.writeShellApplication {
    name = "${name}-packaged";
    text = ''
      exec ${framPkg}/bin/${name} "$@"
    '';
  };
  liveCommands = builtins.map mkLive commands;
  packagedCommands = builtins.map mkPackaged commands;
in
{
  options.myConfig.modules.fram.enable = lib.mkEnableOption "checkout-first Fram CLI suite with pinned helper compatibility";
  config = lib.mkIf config.myConfig.modules.fram.enable {
    environment.systemPackages = (liveCommands ++ packagedCommands ++ [ (lib.lowPrio framPkg) ]);
  };
}
