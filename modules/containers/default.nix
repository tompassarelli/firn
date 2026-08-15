{ config, lib, pkgs, ... }:

((username: {
  options.myConfig.modules.containers.enable = lib.mkEnableOption "Podman containers with Distrobox";
  config = lib.mkIf config.myConfig.modules.containers.enable {
    virtualisation.podman = {
      enable = true;
      dockerCompat = true;
      defaultNetwork.settings.dns_enabled = true;
    };
    users.users.${username}.extraGroups = [ "podman" ];
    environment.systemPackages = with pkgs; [ distrobox podman-compose ];
  };
}) config.myConfig.modules.users.username)
