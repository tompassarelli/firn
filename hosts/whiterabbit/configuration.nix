{ config, lib, pkgs, ... }:

{
  myConfig.modules.system.stateVersion = "25.05";
  myConfig.modules.users.enable = true;
  myConfig.modules.users.username = "tom";
  myConfig.modules.users.email = "tom.passarelli@protonmail.com";
  myConfig.modules.users.fullName = "tompassarelli";
  myConfig.modules.nix-settings.enable = true;
  myConfig.modules.boot.enable = true;
  myConfig.modules.networking.enable = true;
  myConfig.modules.remmina.enable = true;
  myConfig.modules.timezone.enable = true;
  myConfig.modules.timezone.zone = "Asia/Taipei";
  myConfig.modules.ssh.enable = true;
  myConfig.modules.swap.enable = true;
  myConfig.modules.auto-upgrade.enable = true;
  myConfig.modules.framework.enable = true;
  myConfig.modules.framework13-mic.enable = true;
  myConfig.modules.fwupd.enable = true;
  myConfig.modules.thermal-management.enable = true;
  myConfig.modules.pipewire.enable = true;
  myConfig.modules.bluetooth.enable = false;
  myConfig.modules.input.enable = true;
  myConfig.modules.piper.enable = false;
  myConfig.modules.g203-led.enable = true;
  myConfig.modules.kanata = {
    enable = true;
    configFile = ../../dotfiles/kanata/kanata.kbd;
    port = 7070;
    extraArgs = [ "--debug" "--log-layer-changes" ];
    devices = [
      "/dev/input/event0"
      "/dev/input/by-id/usb-Kingsis_Peripherals_ZOWIE_Gaming_mouse-event-mouse"
      "/dev/input/by-id/usb-Logitech_G102_LIGHTSYNC_Gaming_Mouse_2072387E5847-event-mouse"
    ];
  };
  myConfig.modules.glide.enable = false;
  myConfig.modules.guix.enable = false;
  myConfig.modules.neovim.enable = true;
  myConfig.modules.mini-serve.enable = true;
  myConfig.modules.awscli.enable = true;
  myConfig.modules.cloudflare-auth.enable = true;
  myConfig.modules.libsecret.enable = true;
  myConfig.modules.proton-autopurge.enable = true;
  myConfig.modules.parted.enable = true;
  myConfig.modules.unixodbc.enable = true;
  myConfig.modules.nix-ld.enable = true;
  myConfig.modules.appimage.enable = true;
  myConfig.modules.codex.enable = true;
  myConfig.modules.hermes.enable = false;
  myConfig.modules.zed.enable = true;
  myConfig.modules.windows-vm.enable = true;
  myConfig.modules.nh.enable = true;
  myConfig.modules.babashka.enable = true;
  myConfig.modules.north-fram.enable = true;
  myConfig.modules.north-stream-sync.enable = false;
  myConfig.modules.north-coordination-workers.enable = false;
  myConfig.modules.agent-slice.enable = true;
  systemd.services.home-manager-tom.serviceConfig.TimeoutStartSec = lib.mkForce "90s";
  myConfig.modules.stylix.chosenTheme = "everforest-dark-hard";
  sops.secrets."wireguard-laptop".sopsFile = ../../secrets/wireguard.yaml;
  networking.wireguard.interfaces.wg0 = {
    ips = [ "10.8.0.2/24" ];
    privateKeyFile = config.sops.secrets.wireguard-laptop.path;
    peers = [
      {
        publicKey = "a7JDSXww46/FU458PmIAcHbGTqkwkMBahtmuFyku+z8=";
        endpoint = "3.18.118.65:51820";
        allowedIPs = [ "10.8.0.1/32" ];
        persistentKeepalive = 25;
      }
    ];
  };
  imports = [ ./_generated-enables.nix ];
}
