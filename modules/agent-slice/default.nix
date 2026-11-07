{ config, lib, ... }:
let
  cfg = config.myConfig.modules.agent-slice;
  username = config.myConfig.modules.users.username;
  harnessSlices = [
    "agent.slice"
    "control.slice"
  ];
  runsNorth =
    service:
    lib.any (lib.hasSuffix "/bin/north") (
      lib.take 2 (lib.splitString " " (toString (service.Service.ExecStart or "")))
    );
  escapedUnits = lib.attrNames (
    lib.filterAttrs (
      _: service: runsNorth service && !lib.elem (service.Service.Slice or null) harnessSlices
    ) config.home-manager.users.${username}.systemd.user.services
  );
in
{
  options.myConfig.modules.agent-slice = {
    enable = lib.mkEnableOption "agent.slice compute governance — weight-based backpressure so agent lanes yield to the desktop";
    cpuQuotaPercent = lib.mkOption {
      type = lib.types.ints.positive;
      default = 1800;
      description = ''
        Hard CPU ceiling for every agent process on the host, in percent of one CPU (1000 = 10 CPUs).
        CPUWeight only yields under contention; without a ceiling, agent builds that skip capacity admission
        filled all 24 laptop threads (load 150-194 on 2026-11-05) and drew more than the charger supplies.
        The capacity mode tick lowers it at runtime from seat, power source and temperature; this is the ceiling it starts from.
      '';
    };
    controlCpuQuotaPercent = lib.mkOption {
      type = lib.types.ints.positive;
      default = 200;
      description = ''
        Hard CPU ceiling for control.slice, where placement, pace, relay and ledger units run ahead of the agent work they control.
        It keeps the control plane out of agent.slice's quota without leaving it an unbounded way around the envelope (north#834).
      '';
    };
  };
  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = escapedUnits == [ ];
        message = "every user unit that runs north must declare Slice = \"agent.slice\" (or \"control.slice\" for the control plane), so the kernel's CPU envelope covers it (north#834): ${lib.concatStringsSep ", " escapedUnits}";
      }
    ];
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
          CPUQuota = "${toString cfg.controlCpuQuotaPercent}%";
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
