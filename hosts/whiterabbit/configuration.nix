{ config, lib, pkgs, ... }:

{
  myConfig.modules.system.stateVersion = "25.05";
  myConfig.modules.users.enable = true;
  myConfig.modules.users.username = "tom";
  myConfig.modules.users.email = "6378995+tompassarelli@users.noreply.github.com";
  myConfig.modules.users.fullName = "tompassarelli";
  myConfig.modules.nix-settings.enable = true;
  myConfig.modules.boot.enable = true;
  myConfig.modules.networking.enable = true;
  myConfig.modules.remmina.enable = true;
  myConfig.modules.timezone.enable = true;
  myConfig.modules.timezone.zone = "Asia/Taipei";
  myConfig.modules.ssh.enable = true;
  myConfig.modules.swap.enable = true;
  myConfig.modules.tmp-retention.enable = true;
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
    extraArgs = [ "--log-layer-changes" ];
    devices = [
      "/dev/input/event0"
      "/dev/input/by-id/usb-Kingsis_Peripherals_ZOWIE_Gaming_mouse-event-mouse"
      "/dev/input/by-id/usb-Logitech_G102_LIGHTSYNC_Gaming_Mouse_2072387E5847-event-mouse"
    ];
  };
  myConfig.modules.glide.enable = false;
  myConfig.modules.guix.enable = false;
  myConfig.modules.neovim.enable = true;
  myConfig.modules.vscode.enable = true;
  myConfig.modules.mini-serve.enable = true;
  myConfig.modules.awscli.enable = true;
  myConfig.modules.bitwarden-desktop.enable = true;
  myConfig.modules.cloudflare-auth.enable = true;
  myConfig.modules.libsecret.enable = true;
  myConfig.modules.proton-autopurge.enable = true;
  myConfig.modules.parted.enable = true;
  myConfig.modules.unixodbc.enable = true;
  myConfig.modules.nix-ld.enable = true;
  myConfig.modules.musl.enable = true;
  myConfig.modules.appimage.enable = true;
  myConfig.modules.codex.enable = true;
  myConfig.modules.codex-runtime.enable = true;
  myConfig.modules.claude.enable = true;
  myConfig.modules.windows-vm.enable = false;
  myConfig.modules.nh.enable = true;
  myConfig.modules.agent-slice.enable = true;
  myConfig.modules.delivery-liveness.enable = true;
  myConfig.modules.lane-gc.enable = true;
  myConfig.modules.worker-ledger.enable = true;
  myConfig.modules.capacity-watchdog.enable = true;
  systemd.services.home-manager-tom.serviceConfig.TimeoutStartSec = lib.mkForce "90s";
  services.udev.extraHwdb = "evdev:input:b0018v32ACp0006*\n KEYBOARD_KEY_100c6=f10\n";
  myConfig.modules.airplane.enable = true;
  myConfig.modules.stylix.chosenTheme = "everforest-dark-hard";
  sops.secrets = {
    "wireguard-laptop" = { };
    "vastai-api-key" = {
      key = "api_key";
      owner = "tom";
      mode = "0400";
    };
    "bnet" = {
      key = "";
      owner = "tom";
      mode = "0400";
    };
  };
  myConfig.modules.wg-nexus = {
    enable = true;
    role = "client";
  };
  myConfig.modules.nexus-pull.enable = true;
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
