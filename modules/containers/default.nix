{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.myConfig.modules.containers;
  username = config.myConfig.modules.users.username;
in
{
  options.myConfig.modules.containers.enable = lib.mkEnableOption "Podman containers with Distrobox";
  config = lib.mkIf cfg.enable {
    virtualisation.podman = {
      enable = true;
      dockerCompat = true;
      defaultNetwork.settings.dns_enabled = true;
    };
    users.users.${username}.extraGroups = [ "podman" ];
    environment.systemPackages = with pkgs; [
      distrobox
      podman-compose
    ];
  };
}
