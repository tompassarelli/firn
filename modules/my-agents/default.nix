{ config, lib, pkgs, ... }:

{
  options.myConfig.modules.my-agents.enable = lib.mkEnableOption "my-agents — teach-only shim (folded into `north dashboard`)";
  config = lib.mkIf config.myConfig.modules.my-agents.enable {
    environment.systemPackages = [
      (pkgs.writeShellScriptBin "my-agents" ''
        echo 'moved: north dashboard   (also: north doctor · north — the card)' >&2; exit 1
      '')
    ];
  };
}
