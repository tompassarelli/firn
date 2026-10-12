{ config, lib, pkgs, ... }:

{
  myConfig.modules.system.stateVersion = "25.05";
  myConfig.modules.users.enable = true;
  myConfig.modules.users.username = "tom";
  myConfig.modules.users.fullName = "tompassarelli";
  myConfig.modules.chrome.default = true;
  myConfig.modules.nix-settings.enable = true;
  myConfig.modules.boot.enable = true;
  myConfig.modules.networking.enable = true;
  myConfig.modules.remmina.enable = true;
  myConfig.modules.timezone.enable = true;
  myConfig.modules.ssh.enable = false;
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
  };
  myConfig.modules.glide.enable = false;
  myConfig.modules.guix.enable = false;
  myConfig.modules.neovim.enable = true;
  myConfig.modules.vscode.enable = true;
  myConfig.modules.mini-serve.enable = true;
  myConfig.modules.bitwarden-desktop.enable = true;
  myConfig.modules.libsecret.enable = true;
  myConfig.modules.parted.enable = true;
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
  myConfig.modules.capacity-watchdog.rest = {
    system = [
      "auto-cpufreq.service"
      "dbus-broker.service"
      "getty@*.service"
      "kanata-*.service"
      "mini-serve.service"
      "NetworkManager.service"
      "wpa_supplicant.service"
      "nix-daemon.service"
      "nscd.service"
      "polkit.service"
      "rfkill-guard.service"
      "systemd-journald.service"
      "systemd-logind.service"
      "systemd-oomd.service"
      "systemd-resolved.service"
      "systemd-timesyncd.service"
      "systemd-udevd.service"
      "user@*.service"
      "wireguard-watchdog.service"
      "init.scope"
      "session-*.scope"
      "logrotate.timer"
      "systemd-tmpfiles-clean.timer"
      "nixos-upgrade.timer"
      "nix-gc.timer"
      "fstrim.timer"
    ];
    user = [
      "niri.service"
      "quickshell.service"
      "swaybg.service"
      "swayidle.service"
      "wl-clip-persist.service"
      "wl-gammarelay.service"
      "emacs.service"
      "pipewire.service"
      "pipewire-pulse.service"
      "wireplumber.service"
      "xdg-desktop-portal*.service"
      "xdg-document-portal.service"
      "xdg-permission-store.service"
      "gvfs-daemon.service"
      "gcr-ssh-agent.service"
      "dbus-broker.service"
      "app-nm*applet@autostart.service"
      "activity-daemon.service"
      "socrates-chat.service"
      "capacity-watchdog.service"
      "wc3-controller.service"
      "init.scope"
      "laptop-runner.timer"
      "worker-ledger.timer"
      "agents-flow-stall.timer"
      "watch-alerts.timer"
      "vast-reaper.timer"
      "lane-gc.timer"
      "lane-gc-remote.timer"
      "nexus-pull.timer"
      "nexus-restore-test.timer"
      "machine-update.timer"
      "git-maintenance-nightly.timer"
      "agent-runtime-update.timer"
      "firn-delivery-liveness.timer"
      "model-watch.timer"
      "skill-prune.timer"
      "supply-chain-scan.timer"
      "cross-project-scan.timer"
      "proton-log-watchdog.timer"
      "proton-spam-autopurge.timer"
      "systemd-tmpfiles-clean.timer"
    ];
    sockets = [
      "* 127.0.0.53:53 systemd-resolved.service"
      "* 127.0.0.54:53 systemd-resolved.service"
      "* *:5353 systemd-resolved.service"
      "* *:5355 systemd-resolved.service"
      "tcp 127.0.0.1:7070 kanata-*.service"
      "tcp 127.0.0.1:39847 mini-serve.service"
      "tcp 127.0.0.1:* wc3-controller.service"
      "udp *:* -"
    ];
    cores = 0.02;
    budgets = [
      "auto-cpufreq.service 0.08"
      "niri.service 0.06"
      "activity-daemon.service 0.05"
      "socrates-chat.service 0.04"
      "wireguard-watchdog.service 0.03"
    ];
  };
  systemd.services.home-manager-tom.serviceConfig.TimeoutStartSec = lib.mkForce "90s";
  services.udev.extraHwdb = "evdev:input:b0018v32ACp0006*\n KEYBOARD_KEY_100c6=f10\n";
  myConfig.modules.airplane.enable = true;
  myConfig.modules.stylix.chosenTheme = "everforest-dark-hard";
  myConfig.modules.nexus-pull.enable = true;
  imports = [ ./_generated-enables.nix ];
}
