{
  config,
  lib,
  pkgs,
  ...
}:

let
  username = config.myConfig.modules.users.username;
  homeDir = config.myConfig.modules.users.homeDir;
  cfg = config.myConfig.modules.nexus-hardening;
  inherit (cfg) wgAddress;
  wgInterface = "wg-nexus";
  creds = " -p wa -k nexus-creds";
  inherit (cfg) upgradeFlake;
  deployScript = pkgs.writeShellScript "nexus-deploy" ''
    set -euo pipefail
    top="$1"
    [[ "$top" =~ ^/nix/store/[a-z0-9]{32}-nixos-system-[A-Za-z0-9._+-]+$ ]] || { echo "refusing $top: not a nixos-system store path" >&2; exit 2; }
    nix-store --check-validity "$top"
    [[ -x "$top/bin/switch-to-configuration" ]] || { echo "refusing $top: no switch-to-configuration" >&2; exit 2; }
    nix-env --profile /nix/var/nix/profiles/system --set "$top"
    booted="$(readlink /run/booted-system/{initrd,kernel,kernel-modules})"
    built="$(readlink "$top"/{initrd,kernel,kernel-modules})"
    if [[ "$booted" == "$built" ]]; then action=switch; else action=boot; fi
    "$top/bin/switch-to-configuration" "$action"
  '';
in
{
  options.myConfig.modules.nexus-hardening = {
    enable = lib.mkEnableOption "nexus server hardening: WireGuard-only sshd, nftables, no sudo, auto-upgrade, audit, memory protection";
    upgradeFlake = lib.mkOption {
      type = lib.types.str;
      description = "flake reference the daily auto-upgrade and nexus-upgrade build, e.g. github:OWNER/REPO#nexus";
    };
    wgAddress = lib.mkOption {
      type = lib.types.str;
      default = "10.77.0.1";
      description = "wg-nexus address sshd listens on";
    };
    publicSsh = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "also serve key-only sshd on every address with port 22 open, for a first boot before the wg-nexus handshake is verified";
    };
    deployKeys = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Nix public keys whose signature makes a pushed system closure importable by the login user; with one set, `systemctl start nexus-deploy` activates that nixos-system store path as root, so a deployer builds the closure elsewhere and the host never evaluates or builds its own";
    };
    publicTcpPorts = lib.mkOption {
      type = lib.types.listOf lib.types.port;
      default = [ ];
      description = "TCP ports open on every address besides sshd's, for services the host exposes to the internet";
    };
  };
  config = lib.mkIf cfg.enable {
    myConfig.modules = {
      ssh.enable = true;
      polkit.enable = true;
      auto-upgrade.enable = true;
    };
    services = {
      openssh = {
        openFirewall = false;
        listenAddresses =
          if cfg.publicSsh then
            [ ]
          else
            [
              {
                addr = wgAddress;
                port = 22;
              }
            ];
        settings = {
          PermitRootLogin = "no";
          AllowUsers = [ username ];
        };
      };
      journald = {
        storage = "persistent";
        extraConfig = ''
          SystemMaxUse=1G
          MaxRetentionSec=30day

        '';
      };
      resolved.settings.Resolve = {
        LLMNR = "false";
        MulticastDNS = "false";
      };
      earlyoom.enable = true;
    };
    systemd = {
      services = {
        sshd = {
          wants = [ "network-online.target" ];
          after = [ "network-online.target" ];
        };
        "nexus-deploy@" = lib.mkIf (cfg.deployKeys != [ ]) {
          description = "Activate the pushed system closure %f";
          restartIfChanged = false;
          stopIfChanged = false;
          path = [
            config.nix.package
            pkgs.coreutils
          ];
          serviceConfig = {
            Type = "oneshot";
            ExecStart = "${deployScript} %f";
          };
        };
        nexus-upgrade = {
          description = "Run the NixOS auto-upgrade from the upgrade flake now";
          serviceConfig = {
            Type = "oneshot";
            ExecStart = "${pkgs.systemd}/bin/systemctl start nixos-upgrade.service";
          };
        };
      };
      tmpfiles.rules = [
        "d ${homeDir}/.ssh 0700 ${username} users -"
        "d ${homeDir}/.claude 0700 ${username} users -"
        "d ${homeDir}/.codex 0700 ${username} users -"
      ];
    };
    networking = {
      nftables.enable = true;
      firewall = {
        enable = true;
        allowPing = true;
        allowedTCPPorts = lib.mkForce ((lib.optional cfg.publicSsh 22) ++ cfg.publicTcpPorts);
        allowedTCPPortRanges = lib.mkForce [ ];
        allowedUDPPorts = lib.optional (
          config.myConfig.modules.wg-nexus.enable && config.myConfig.modules.wg-nexus.role == "hub"
        ) 51820;
        interfaces.${wgInterface}.allowedTCPPorts = [ 22 ];
      };
    };
    security = {
      sudo.enable = false;
      sudo-rs.enable = false;
      polkit = {
        adminIdentities = [ "unix-user:0" ];
        extraConfig = ''
          polkit.addRule(function(action, subject) {
            if (action.id == 'org.freedesktop.systemd1.manage-units' && subject.user == '${username}' &&
                action.lookup('unit') == 'nexus-upgrade.service' && action.lookup('verb') == 'start') {
              return polkit.Result.YES;
            }
          });

        ''
        + lib.optionalString (cfg.deployKeys != [ ]) ''
          polkit.addRule(function(action, subject) {
            if (action.id == 'org.freedesktop.systemd1.manage-units' && subject.user == '${username}' &&
                action.lookup('unit').indexOf('nexus-deploy@') == 0 && action.lookup('verb') == 'start') {
              return polkit.Result.YES;
            }
          });

        '';
      };
      audit = {
        enable = lib.mkDefault true;
        rules = [
          "-w /etc/ssh${creds}"
          "-w ${homeDir}/.ssh${creds}"
          "-w ${homeDir}/.claude/.credentials.json${creds}"
          "-w ${homeDir}/.codex/auth.json${creds}"
          "-a always,exit -F arch=b64 -S execve -F euid=0 -F auid>=1000 -F auid!=unset -k nexus-privesc"
        ];
      };
      auditd.enable = true;
    };
    nix.settings.extra-trusted-public-keys = cfg.deployKeys;
    system.autoUpgrade = {
      flake = lib.mkForce upgradeFlake;
      flags = lib.mkForce [
        "--refresh"
        "--flake ${upgradeFlake}"
      ];
      dates = lib.mkForce "20:00";
      allowReboot = lib.mkForce true;
      rebootWindow = {
        lower = "20:00";
        upper = "21:00";
      };
    };
    users.allowNoPasswordLogin = true;
    boot.kernel.sysctl = {
      "net.ipv4.ip_nonlocal_bind" = 1;
      "net.ipv4.conf.all.rp_filter" = 1;
      "net.ipv4.conf.default.rp_filter" = 1;
      "net.ipv4.conf.all.accept_redirects" = 0;
      "net.ipv4.conf.default.accept_redirects" = 0;
      "net.ipv4.conf.all.secure_redirects" = 0;
      "net.ipv4.conf.default.secure_redirects" = 0;
      "net.ipv4.conf.all.send_redirects" = 0;
      "net.ipv4.conf.default.send_redirects" = 0;
      "net.ipv6.conf.all.accept_redirects" = 0;
      "net.ipv6.conf.default.accept_redirects" = 0;
      "net.ipv4.conf.all.accept_source_route" = 0;
      "net.ipv4.conf.default.accept_source_route" = 0;
      "net.ipv6.conf.all.accept_source_route" = 0;
      "net.ipv6.conf.default.accept_source_route" = 0;
      "net.ipv4.conf.all.log_martians" = 1;
      "net.ipv4.icmp_echo_ignore_broadcasts" = 1;
      "net.ipv4.tcp_syncookies" = 1;
      "kernel.kptr_restrict" = 2;
      "kernel.dmesg_restrict" = 1;
      "kernel.unprivileged_bpf_disabled" = 1;
      "net.core.bpf_jit_harden" = 2;
      "fs.protected_hardlinks" = 1;
      "fs.protected_symlinks" = 1;
      "vm.swappiness" = 180;
      "vm.page-cluster" = 0;
    };
    zramSwap = {
      enable = true;
      memoryPercent = 100;
    };
    swapDevices = [
      {
        device = "/var/lib/swapfile";
        size = 8192;
      }
    ];
  };
}
