{
  config,
  lib,
  modulesPath,
  ...
}:

{
  imports = [ "${modulesPath}/installer/scan/not-detected.nix" ];
  boot = {
    initrd = {
      availableKernelModules = [
        "nvme"
        "xhci_pci"
        "thunderbolt"
        "usb_storage"
        "sd_mod"
      ];
      kernelModules = [ ];
      luks.devices.cryptroot.device = "/dev/disk/by-uuid/0fb2764a-15e7-4e38-bbac-5542c5ca2ac2";
    };
    kernelModules = [ "kvm-amd" ];
    extraModulePackages = [ ];
  };
  fileSystems = {
    "/" = {
      device = "/dev/disk/by-uuid/307b1eae-f2ab-4969-886b-08f4a76732dd";
      fsType = "btrfs";
      options = [ "subvol=root" ];
    };
    "/home" = {
      device = "/dev/disk/by-uuid/307b1eae-f2ab-4969-886b-08f4a76732dd";
      fsType = "btrfs";
      options = [ "subvol=home" ];
    };
    "/nix" = {
      device = "/dev/disk/by-uuid/307b1eae-f2ab-4969-886b-08f4a76732dd";
      fsType = "btrfs";
      options = [ "subvol=home" ];
    };
    "/boot" = {
      device = "/dev/disk/by-uuid/7623-7A7C";
      fsType = "vfat";
      options = [
        "fmask=0022"
        "dmask=0022"
      ];
    };
  };
  swapDevices = [ ];
  networking.useDHCP = lib.mkDefault true;
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
