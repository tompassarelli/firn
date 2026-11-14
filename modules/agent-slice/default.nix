{ config, lib, ... }:
let
  cfg = config.myConfig.modules.agent-slice;
  username = config.myConfig.modules.users.username;
  home = config.users.users.${username}.home;
  diskCaps = lib.optionalAttrs cfg.diskCaps {
    IOReadBandwidthMax = "${home} ${toString cfg.diskReadMiBps}M";
    IOWriteBandwidthMax = "${home} ${toString cfg.diskWriteMiBps}M";
  };
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
      default = 400;
      description = ''
        Hard CPU ceiling for control.slice, where placement, pace, relay and ledger units run ahead of the agent work they control.
        It keeps the control plane out of agent.slice's quota without leaving it an unbounded way around the envelope (north#834).
        At 200 it throttled 34% of periods under build load, so usage-sample (55 s start limit) timed out 8 times in 12 h on 2026-11-11 (north#1093).
      '';
    };
    diskCaps = lib.mkEnableOption ''
      a read and a write rate cap for agent.slice and control.slice on the disk under the user's home.
      The disk runs no IO scheduler and io.cost is off, so IOWeight shares nothing; only io.max bounds fleet disk work, and dm-crypt charges its writes to the issuing cgroup on the whole disk, which systemd resolves from the home path.
      The caps name the home path, as north's capacity tick does for its runtime write cap, because systemd keeps one io.max entry per named path and a second name for the same disk overwrites the first one's rates (north#1553)'';
    diskReadMiBps = lib.mkOption {
      type = lib.types.ints.positive;
      default = 200;
      description = ''
        Read rate in MiB/s each of agent.slice and control.slice may draw from the disk under the home path.
        A guess: on 2026-11-14 at 11:02 PM control.slice read 646 MB/s and agent.slice 67 MB/s while app.slice sat at 79% full IO stall; three app.slice io.pressure readings with full avg300 under 5 at the fleet's evening load settle it (north#1553).
      '';
    };
    diskWriteMiBps = lib.mkOption {
      type = lib.types.ints.positive;
      default = 200;
      description = ''
        Write rate in MiB/s each of agent.slice and control.slice may submit to the disk under the home path.
        The rate north's capacity tick had applied at runtime since a 2026-11-13 capture saw agent.slice writeback bursts of 1 to 2.3 GB/s; it now holds from boot (north#1553).
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
        }
        // diskCaps;
      };
      control = {
        description = "North control timers — placement, pace, relay and ledger run ahead of the agent work they control";
        sliceConfig = {
          CPUWeight = 250;
          CPUQuota = "${toString cfg.controlCpuQuotaPercent}%";
          IOWeight = 250;
        }
        // diskCaps;
      };
      app.sliceConfig.MemoryLow = "12G";
      session.sliceConfig = {
        CPUWeight = 300;
        IOWeight = 300;
      };
    };
  };
}
