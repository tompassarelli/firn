{ config, lib, pkgs, ... }:

{
  options.myConfig.modules.boot.enable = lib.mkEnableOption "boot configuration";
  config = lib.mkIf config.myConfig.modules.boot.enable {
    boot.loader.systemd-boot.enable = true;
    boot.loader.efi.canTouchEfiVariables = true;
    boot.kernelModules = [ "uinput" ];
    boot.kernelParams = [ "amdgpu.gpu_recovery=1" ];
    boot.kernel.sysctl = {
      "kernel.hardlockup_panic" = 1;
      "kernel.softlockup_panic" = 1;
      "kernel.panic_on_oops" = 1;
      "kernel.panic" = 20;
    };
    boot.crashDump.enable = true;
    boot.crashDump.reservedMemory = "512M";
  };
}
