{ config, lib, ... }:
let
  cfg = config.myConfig.modules.ssh;
in
{
  config = lib.mkIf cfg.enable {
    services.openssh = {
      enable = true;
      settings = {
        KbdInteractiveAuthentication = false;
        PasswordAuthentication = false;
      };
    };
  };
  options.myConfig.modules.ssh.enable = lib.mkEnableOption "SSH server";
}
