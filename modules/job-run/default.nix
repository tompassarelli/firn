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
in
{
  _module.args.northBin = northBin;
  _module.args.jobRun =
    name: cmd:
    "${pkgs.bash}/bin/bash ${northBin}/job-run --path ${recordPath} --user ${username} ${name} -- ${cmd}";
  assertions = [
    {
      assertion = checkoutReaders == [ ];
      message = "scheduled jobs must run north code from the promoted runtime (${northBin}), not the north checkout: ${lib.concatStringsSep ", " checkoutReaders}";
    }
  ];
}
