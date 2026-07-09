{ config, lib, pkgs, ... }:

{
  options.myConfig.modules.my-agents.enable = lib.mkEnableOption "My-agents — cockpit command for the agentic stack";
  config = lib.mkIf config.myConfig.modules.my-agents.enable {
    environment.systemPackages = [
      (pkgs.writeShellScriptBin "my-agents" ''
        exec /home/tom/code/convoy/bin/my-agents "$@"
      '')
      (pkgs.writeShellScriptBin "myag" ''
        exec /home/tom/code/convoy/bin/my-agents "$@"
      '')
    ];
  };
}
