{ config, lib, pkgs, ... }:

{
  options.myConfig.modules.swap.enable = lib.mkEnableOption "zram-based compressed swap";
  config = lib.mkIf config.myConfig.modules.swap.enable {
    zramSwap.enable = true;
    zramSwap.algorithm = "zstd";
    zramSwap.memoryPercent = 50;
    swapDevices = [
      {
        device = "/swap/swapfile";
        priority = 0;
      }
    ];
    boot.resumeDevice = "/dev/mapper/cryptroot";
    boot.kernelParams = [ "resume_offset=347227782" ];
    boot.kernel.sysctl = {
      "vm.swappiness" = 180;
      "vm.watermark_boost_factor" = 0;
      "vm.watermark_scale_factor" = 125;
      "vm.page-cluster" = 0;
    };
  };
}
