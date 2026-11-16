{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.myConfig.modules.job-run;
  homeDir = config.myConfig.modules.users.homeDir;
  username = config.myConfig.modules.users.username;
  northBin = "${homeDir}/.local/state/north/current/tree/bin";
  unitPath = lib.concatStringsSep ":" [
    "${homeDir}/.nix-profile/bin"
    "/etc/profiles/per-user/${username}/bin"
    "/run/wrappers/bin"
    "/run/current-system/sw/bin"
    northBin
    "${homeDir}/.local/bin"
    "${homeDir}/.local/share/firn/bin"
  ];
  recordPath = lib.makeBinPath [
    pkgs.bash
    pkgs.python3
    pkgs.openssh
    pkgs.coreutils
    pkgs.util-linux
    pkgs.hostname
  ];
  strings =
    value:
    if lib.isString value then
      [ value ]
    else if lib.isList value then
      lib.concatMap strings value
    else if lib.isDerivation value then
      [ (toString value) ]
    else if lib.isAttrs value then
      lib.concatMap strings (lib.attrValues value)
    else
      [ ];
  namesCheckout =
    text:
    lib.any (path: lib.hasInfix path text) [
      "/.local/share/north"
      "/code/north/main"
    ]
    || lib.hasInfix "/.local/bin" (lib.head (lib.splitString northBin text));
  readsCheckout = unit: lib.any namesCheckout (strings unit);
  timedUnits =
    services: timers: unitOf:
    lib.mapAttrsToList (name: timer: {
      inherit name;
      unit = services.${lib.removeSuffix ".service" (unitOf name timer)} or { };
    }) timers;
  userTimed =
    let
      user = config.home-manager.users.${username}.systemd.user;
    in
    timedUnits user.services user.timers (name: timer: timer.Timer.Unit or name);
  systemTimed = timedUnits (lib.mapAttrs (_: service: {
    inherit (service)
      serviceConfig
      environment
      script
      preStart
      postStart
      ;
    path = map toString service.path;
  }) config.systemd.services) config.systemd.timers (name: timer: timer.timerConfig.Unit or name);
  checkoutReaders = map (job: job.name) (
    lib.filter (job: readsCheckout job.unit) (userTimed ++ systemTimed)
  );
  runner = "${northBin}/north job-run ";
  scratchRoot = "/run/north-scratch";
  scratch = lib.optionalString (cfg.scratchInMemory != null) " --scratch ${scratchRoot}";
  bash = "${pkgs.bash}/bin/bash";
  bashDirs = [
    "/run/current-system/sw/bin"
    "${pkgs.bash}/bin"
    "${pkgs.bashInteractive}/bin"
  ];
  findsBash = path: lib.any (dir: lib.elem dir bashDirs) (lib.splitString ":" path);
  jobProgram = line: lib.head (lib.splitString " " (lib.elemAt (lib.splitString " -- " line) 1));
  needsBash =
    line:
    lib.hasInfix runner line
    && (!lib.hasPrefix "${bash} " line || !lib.hasPrefix builtins.storeDir (jobProgram line));
  pathIn =
    environment: fallback:
    let
      set = lib.findFirst (lib.hasPrefix "PATH=") null (strings environment);
    in
    if set == null then fallback else lib.removePrefix "PATH=" set;
  userJobs = lib.mapAttrsToList (name: service: {
    inherit name;
    lines = strings (service.Service or { });
    path = pathIn (service.Service.Environment or [ ]) "/run/current-system/sw/bin";
  }) config.home-manager.users.${username}.systemd.user.services;
  systemJobs = lib.mapAttrsToList (name: service: {
    inherit name;
    lines = strings service.serviceConfig;
    path = pathIn (service.serviceConfig.Environment or [ ]) (service.environment.PATH or "");
  }) config.systemd.services;
  bashlessJobs = map (job: job.name) (
    lib.filter (job: lib.any needsBash job.lines && !findsBash job.path) (userJobs ++ systemJobs)
  );
in
{
  options.myConfig.modules.job-run.scratchInMemory = lib.mkOption {
    type = lib.types.nullOr lib.types.ints.positive;
    default = null;
    description = ''
      When set, /run/north-scratch is a tmpfs of this many GiB owned by the user, and every unit started through jobRun gets a fresh
      TMPDIR there (/run/north-scratch/NAME, memory), which north job-run empties before the job and removes after it. A mount of its own,
      not the runtime directory, so a job that fills its scratch cannot fill the desktop's sockets and pipes beside it.
      On 2026-11-16 the laptop's /tmp was the encrypted btrfs root: runtime follow's canary wrote about 1 GB of scratch a tick there and
      stalled the desktop, and killed runs had left 106 GB in about 6,000 directories (north#1553).
      Build hosts leave it unset: they have no desktop to stall, their scratch sits beside builds on a disk the lease reaper trims,
      and their memory is held for builds.
      The size is a guess over the canary's 1.3 GB peak a run; a job refused for ENOSPC in its TMPDIR would settle it.
    '';
  };
  config = {
    fileSystems.${scratchRoot} = lib.mkIf (cfg.scratchInMemory != null) {
      device = "tmpfs";
      fsType = "tmpfs";
      options = [
        "size=${toString cfg.scratchInMemory}G"
        "mode=0700"
        "nosuid"
        "nodev"
      ];
    };
    systemd.services.north-scratch-owner = lib.mkIf (cfg.scratchInMemory != null) {
      description = "Give the scratch tmpfs to the user as soon as it is mounted, at boot or on a live switch";
      after = [ "run-north\\x2dscratch.mount" ];
      bindsTo = [ "run-north\\x2dscratch.mount" ];
      wantedBy = [ "run-north\\x2dscratch.mount" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${pkgs.coreutils}/bin/chown ${username}:${
          config.users.users.${username}.group
        } ${scratchRoot}";
      };
    };
    _module.args = {
      inherit northBin unitPath;
      jobRun =
        name: cmd:
        "${bash} ${northBin}/north job-run --path ${recordPath} --user ${username}${scratch} ${name} -- ${cmd}";
    };
    assertions = [
      {
        assertion = checkoutReaders == [ ];
        message = "scheduled jobs must run north code from the promoted runtime (${northBin}), not the north checkout: ${lib.concatStringsSep ", " checkoutReaders}";
      }
      {
        assertion = bashlessJobs == [ ];
        message = "a unit running north job-run must find bash on its PATH, since the promoted north tree's programs start with #!/usr/bin/env bash (put ${pkgs.bash}/bin or /run/current-system/sw/bin on it): ${lib.concatStringsSep ", " bashlessJobs}";
      }
    ];
  };
}
