{ config, lib, pkgs, ... }:

{
  options.myConfig.modules.agent-slice.enable = lib.mkEnableOption "agent.slice compute governance — weight-based backpressure so agent lanes yield to the desktop";
  config = lib.mkIf config.myConfig.modules.agent-slice.enable {
    systemd.user.slices.agent = {
      description = "Agent lanes — yielding compute class";
      sliceConfig = {
        CPUWeight = 20;
        IOWeight = 20;
        MemoryHigh = "61G";
      };
    };
    systemd.user.slices.session.sliceConfig = {
      CPUWeight = 300;
      IOWeight = 300;
    };
  };
}
