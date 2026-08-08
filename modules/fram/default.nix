{ config, lib, pkgs, inputs, ... }:

let
  homeDir = config.myConfig.modules.users.homeDir;
  framPkg = "${homeDir}/code/fram/main";
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
  framCodeStatus = pkgs.writeShellApplication {
    name = "fram-code-status";
    runtimeInputs = ((with pkgs; [
      bash
      coreutils
      findutils
      gawk
      git
      gnugrep
      procps
    ]) ++ (lib.optionals pkgs.stdenv.hostPlatform.isLinux (with pkgs; [ iproute2 ])));
    text = builtins.readFile "${inputs.fram}/bin/fram-code-status";
  };
  devCommandNames = [ "fram" "fram-server" "fram-mcp" "fram-primer" "fram-up" "fram-code-author" ];
  packagedCommandNames = [ "fram" "fram-server" "fram-mcp" "fram-primer" ];
  mkDev = name: pkgs.writeShellApplication {
    name = "${name}-dev";
    runtimeInputs = liveInputs;
    text = ''
      checkout=''${FRAM_CHECKOUT:-$HOME/code/fram/main}
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
      exec ${framPkg}/bin/${name} "$@"
    '';
  };
  mkLive = name: pkgs.writeShellApplication {
    name = name;
    runtimeInputs = liveInputs;
    text = ''
      exec ${framPkg}/bin/${name} "$@"
    '';
  };
  devCommands = builtins.map mkDev devCommandNames;
  packagedCommands = builtins.map mkPackaged packagedCommandNames;
  liveCommands = builtins.map mkLive packagedCommandNames;
in
{
  options.myConfig.modules.fram.enable = lib.mkEnableOption "immutable Fram core commands with explicit checkout-only development commands";
  config = lib.mkIf config.myConfig.modules.fram.enable {
    environment.systemPackages = ([ framCodeStatus ] ++ liveCommands ++ devCommands ++ packagedCommands);
  };
}
