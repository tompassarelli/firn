{ config, lib, pkgs, ... }:

{
  myConfig.modules.system.stateVersion = "26.05";
  myConfig.modules.users.enable = true;
  myConfig.modules.users.username = "tom";
  myConfig.modules.users.mutable = false;
  myConfig.modules.users.authorizedKeys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFJ2c3khPX8NgkazmQdEI1kU9IrEZuE8m2/2OIquQbgh tom@nexus"
  ];
  myConfig.modules.users.passwordHashSopsFile = ../../secrets/nexus/console.yaml;
  myConfig.modules.nix-settings.enable = true;
  myConfig.modules.timezone.enable = true;
  myConfig.modules.timezone.zone = "Asia/Taipei";
  imports = [ ./_generated-enables.nix ];
}
