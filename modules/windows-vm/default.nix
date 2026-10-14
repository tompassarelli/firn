{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.windows-vm;
in
{
  config = lib.mkIf cfg.enable {
    boot.kernel.sysctl."net.ipv4.ip_forward" = 1;
    environment.systemPackages = [
      pkgs.spice-gtk
      pkgs.virtio-win
    ];
    networking.firewall.interfaces.virbr0 = {
      allowedTCPPorts = [
        445
        139
      ];
      allowedUDPPorts = [
        137
        138
      ];
    };
    programs.virt-manager.enable = true;
    services.samba = {
      enable = true;
      settings = {
        global = {
          "hosts allow" = "192.168.122. 127.0.0.1 localhost";
          "hosts deny" = "0.0.0.0/0";
          security = "user";
          "server string" = "NixOS";
          workgroup = "WORKGROUP";
        };
        shared = {
          browseable = "yes";
          "create mask" = "0644";
          "directory mask" = "0755";
          path = "/home/${config.myConfig.modules.users.username}/shared";
          "read only" = "no";
          "valid users" = config.myConfig.modules.users.username;
        };
      };
    };
    users.users.${config.myConfig.modules.users.username}.extraGroups = [ "libvirtd" ];
    virtualisation.libvirtd = {
      enable = true;
      qemu = {
        package = pkgs.qemu_kvm;
        swtpm.enable = true;
      };
    };
  };
  options.myConfig.modules.windows-vm.enable =
    lib.mkEnableOption "Windows VM via QEMU/KVM with virt-manager";
}
