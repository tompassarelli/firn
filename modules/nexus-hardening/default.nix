{ config, lib, pkgs, ... }:

((username: ((homeDir: ((wgAddress: ((wgInterface: ((creds: {
  options.myConfig.modules.nexus-hardening.enable = lib.mkEnableOption "nexus server hardening: WireGuard-only sshd, nftables, no sudo, auto-upgrade, audit, memory protection";
  config = lib.mkIf config.myConfig.modules.nexus-hardening.enable {
    myConfig.modules.ssh.enable = true;
    myConfig.modules.polkit.enable = true;
    myConfig.modules.auto-upgrade.enable = true;
    services.openssh = {
      openFirewall = false;
      listenAddresses = [
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
    systemd.services.sshd = {
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
    };
    networking.nftables.enable = true;
    networking.firewall = {
      enable = true;
      allowPing = true;
      allowedTCPPorts = lib.mkForce [ ];
      allowedTCPPortRanges = lib.mkForce [ ];
      allowedUDPPorts = [ 51820 ];
      interfaces = {
        ${wgInterface} = {
          allowedTCPPorts = [ 22 ];
        };
      };
    };
    security.sudo.enable = false;
    security.sudo-rs.enable = false;
    security.polkit.adminIdentities = [ "unix-user:0" ];
    security.polkit.extraConfig = ''
      polkit.addRule(function(action, subject) {
        if (action.id == 'org.freedesktop.systemd1.manage-units' && subject.user == '${username}' &&
            action.lookup('unit') == 'nexus-upgrade.service' && action.lookup('verb') == 'start') {
          return polkit.Result.YES;
        }
      });

    '';
    system.autoUpgrade = {
      flake = lib.mkForce "github:tompassarelli/firn#nexus";
      flags = lib.mkForce [ ];
      dates = lib.mkForce "03:30";
      allowReboot = lib.mkForce true;
      rebootWindow = {
        lower = "04:00";
        upper = "05:00";
      };
    };
    systemd.services.nexus-upgrade = {
      description = "Run the NixOS auto-upgrade from firn main now";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.systemd}/bin/systemctl start nixos-upgrade.service";
      };
    };
    services.journald.storage = "persistent";
    services.journald.extraConfig = ''
      SystemMaxUse=1G
      MaxRetentionSec=30day

    '';
    security.audit.enable = lib.mkDefault true;
    security.auditd.enable = true;
    security.audit.rules = [
      "-w /etc/ssh${creds}"
      "-w ${homeDir}/.ssh${creds}"
      "-w ${homeDir}/.claude/.credentials.json${creds}"
      "-w ${homeDir}/.codex/auth.json${creds}"
      "-a always,exit -F arch=b64 -S execve -F euid=0 -F auid>=1000 -F auid!=unset -k nexus-privesc"
    ];
    services.resolved.llmnr = "false";
    systemd.tmpfiles.rules = [
      "d ${homeDir}/.ssh 0700 ${username} users -"
      "d ${homeDir}/.claude 0700 ${username} users -"
      "d ${homeDir}/.codex 0700 ${username} users -"
    ];
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
    };
    zramSwap = {
      enable = true;
      memoryPercent = 50;
    };
    swapDevices = [
      {
        device = "/var/lib/swapfile";
        size = 8192;
      }
    ];
    services.earlyoom.enable = true;
  };
}) " -p wa -k nexus-creds")) "wg-nexus")) "10.77.0.1")) config.myConfig.modules.users.homeDir)) config.myConfig.modules.users.username)
