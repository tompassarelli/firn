{ lib, ... }:

{
  options.myConfig.modules.glide = {
    enable = lib.mkEnableOption "Glide touchpad motion detection daemon";
    device = lib.mkOption {
      type = lib.types.str;
      default = "/dev/input/by-path/platform-AMDI0010:03-event-mouse";
      description = "Touchpad evdev device path";
    };
    kanataAddress = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1:7070";
      description = "Kanata TCP server address (ip:port)";
    };
    virtualKey = lib.mkOption {
      type = lib.types.str;
      default = "pad-touch";
      description = "Kanata virtual key name to press/release on activation";
    };
    motionThreshold = lib.mkOption {
      type = lib.types.int;
      default = 2;
      description = "Min Euclidean displacement (device abs units) per evdev report to count as motion";
    };
    minStreak = lib.mkOption {
      type = lib.types.int;
      default = 16;
      description = "Consecutive motion-positive samples required to activate (~7ms each, 16 ≈ 112ms)";
    };
  };
  imports = [ ./glide.nix ];
}
