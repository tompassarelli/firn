{ config, lib, ... }:
let
  cfg = config.myConfig.modules.sops-host-key;
in
{
  options.myConfig.modules.sops-host-key.enable =
    lib.mkEnableOption "sops-nix identity from the SSH ed25519 host key instead of /var/lib/sops-nix/key.txt";
  config = lib.mkIf cfg.enable {
    sops = {
      age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
      gnupg.sshKeyPaths = [ ];
    };
  };
}
