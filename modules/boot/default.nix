{ config, lib, pkgs, ... }:

{
  options.myConfig.modules.boot.enable = lib.mkEnableOption "boot configuration";
  config = lib.mkIf config.myConfig.modules.boot.enable {
    boot.loader.systemd-boot.enable = true;
    boot.loader.efi.canTouchEfiVariables = true;
    boot.kernelModules = [ "uinput" ];
    boot.kernelParams = [ "amdgpu.vpe_enable=0" ];
  };
}
