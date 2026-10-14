{ lib, ... }:

{
  options.myConfig.modules.kanata = {
    enable = lib.mkEnableOption "Kanata keyboard remapping";
    devices = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Input device paths for kanata to capture. Find yours with: ls /dev/input/by-id/";
    };
    configFile = lib.mkOption {
      type = lib.types.path;
      description = "Path to kanata .kbd config file";
    };
    port = lib.mkOption {
      type = lib.types.nullOr lib.types.port;
      default = null;
      description = "TCP port for kanata server (e.g. for glide integration)";
    };
    extraArgs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Extra command-line args for kanata (e.g. --debug, --log-layer-changes for diagnosing layer/spacebar seizures)";
    };
  };
  imports = [ ./kanata.nix ];
}
