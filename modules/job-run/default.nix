{
  config,
  lib,
  pkgs,
  ...
}:

let
  homeDir = config.myConfig.modules.users.homeDir;
  username = config.myConfig.modules.users.username;
  northBin = "${homeDir}/.local/state/north/current/tree/bin";
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
  _module.args.northBin = northBin;
  _module.args.jobRun =
    name: cmd:
    "${bash} ${northBin}/north job-run --path ${recordPath} --user ${username} ${name} -- ${cmd}";
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
}
