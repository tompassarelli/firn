{ config, lib, pkgs, ... }:

{
  options.myConfig.modules.convoy.enable = lib.mkEnableOption "Convoy — cockpit command for the agentic stack";
  config = lib.mkIf config.myConfig.modules.convoy.enable {
    environment.systemPackages = [
      (pkgs.writeShellScriptBin "convoy" ''
        exec /home/tom/code/convoy/bin/convoy "$@"
      '')
    ];
  };
}
