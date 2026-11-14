{ lib, ... }:

{
  myConfig.modules = {
    agent-slice.diskCaps = true;
    harness-health.enable = true;
    north-land.enable = true;
    north-land-shadow.enable = true;
    system.stateVersion = "25.05";

    capacity-watchdog = {
      rest = {
        system = [
          "auto-cpufreq.service"
          "dbus-broker.service"
          "getty@*.service"
          "kanata-*.service"
          "mini-serve.service"
          "NetworkManager.service"
          "NetworkManager-dispatcher.service"
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
          "seat-idle-hint.service"
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
          "wm-facts-daemon.service"
          "north-gh-broker.service"
          "capacity-watchdog.service"
          "capacity-taker.service"
          "padbridge.service"
          "dconf.service"
          "app-niri-*.scope"
          "init.scope"
          "laptop-runner.timer"
          "pace-enforcement.timer"
          "harness-health.timer"
          "proxy-terminal-watch.timer"
          "fleet-tick.timer"
          "worker-ledger.timer"
          "agents-flow-stall.timer"
          "ops-check.timer"
          "outside-watch.timer"
          "lane-gc.timer"
          "makgora-goals-perf.timer"
          "makgora-retain.timer"
          "verify-north.timer"
          "nexus-pull.timer"
          "nexus-restore-test.timer"
          "machine-update.timer"
          "git-maintenance-nightly.timer"
          "agent-runtime-update.timer"
          "north-runtime-follow.timer"
          "firn-host-follow.timer"
          "north-strategy-log-retain.timer"
          "north-graph-retain.timer"
          "north-land@*.service"
          "north-stable-hold.service"
          "north-land-shadow.timer"
          "north-land-drill.timer"
          "north-watch.timer"
          "firn-delivery-liveness.timer"
          "skill-prune.timer"
          "convo-retain.timer"
          "mutant-sweep.timer"
          "supply-chain-scan.timer"
          "incident-retro.timer"
          "tool-mine.timer"
          "eta-calibration.timer"
          "north-tempo.timer"
          "usage-sample.timer"
          "watch-review.timer"
          "cross-project-scan.timer"
          "proton-log-watchdog.timer"
          "proton-spam-autopurge.timer"
          "proton-github-bot.timer"
          "systemd-tmpfiles-clean.timer"
        ];
        sockets = [
          "* 127.0.0.53:53 systemd-resolved.service"
          "* 127.0.0.54:53 systemd-resolved.service"
          "* *:5353 systemd-resolved.service"
          "* *:5355 systemd-resolved.service"
          "tcp 127.0.0.1:7070 kanata-*.service"
          "tcp 127.0.0.1:39847 mini-serve.service"
          "tcp 127.0.0.1:* padbridge.service"
          "udp *:* -"
        ];
        cores = builtins.fromJSON "0.02";
        budgets = [
          "auto-cpufreq.service 0.08"
          "niri.service 0.06"
          "activity-daemon.service 0.05"
          "wireguard-watchdog.service 0.03"
        ];
      };
    };

    kanata = {
      configFile = ../../dotfiles/kanata/kanata.kbd;
      port = 7070;
      extraArgs = [ "--log-layer-changes" ];
    };

    users = {
      username = "tom";
      fullName = "tompassarelli";
    };

    chrome.default = true;
    stylix.chosenTheme = "everforest-dark-hard";
  };
  boot.kernel.sysctl = {
    "vm.dirty_background_bytes" = 67108864;
    "vm.dirty_bytes" = 268435456;
  };
  systemd.services.home-manager-tom.serviceConfig.TimeoutStartSec = lib.mkForce "90s";
  services.udev.extraHwdb = ''
    evdev:input:b0018v32ACp0006*
     KEYBOARD_KEY_100c6=f10
  '';
}
