{ config, lib, ... }:
let
  cfg = config.myConfig.modules.agent-slice;
in
{
  options.myConfig.modules.agent-slice = {
    enable = lib.mkEnableOption "agent.slice compute governance — weight-based backpressure so agent lanes yield to the desktop";
    cpuQuotaPercent = lib.mkOption {
      type = lib.types.ints.positive;
      default = 1600;
      description = ''
        Hard CPU ceiling for every agent process on the host, in percent of one CPU (1600 = 16 CPUs).
        CPUWeight only yields under contention; without a ceiling, agent builds that skip capacity admission
        filled all 24 laptop threads (load 150-194 on 2026-11-05) and drew more than the charger supplies.
      '';
    };
  };
  config = lib.mkIf cfg.enable {
    systemd.services."user@".serviceConfig.Delegate = "cpu cpuset io memory pids";
    systemd.user.slices = {
      agent = {
        description = "Agent lanes — yielding compute class";
        sliceConfig = {
          CPUWeight = 20;
          CPUQuota = "${toString cfg.cpuQuotaPercent}%";
          IOWeight = 20;
          MemoryHigh = "61G";
        };
      };
      control = {
        description = "North control timers — placement, pace, relay and ledger run ahead of the agent work they control";
        sliceConfig = {
          CPUWeight = 250;
          IOWeight = 250;
        };
      };
      app.sliceConfig.MemoryLow = "12G";
      session.sliceConfig = {
        CPUWeight = 300;
        IOWeight = 300;
      };
    };
  };
}
