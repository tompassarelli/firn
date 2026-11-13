{ pkgs, whiterabbit }:

let
  inherit (pkgs) lib;
  budget = import ./start-budget.nix;
  user = whiterabbit.config.myConfig.modules.users.username;
  limit =
    whiterabbit.config.home-manager.users.${user}.systemd.user.services.fleet-tick.Service.TimeoutStartSec;
in
if lib.hasSuffix "s" limit && lib.toInt (lib.removeSuffix "s" limit) >= budget.swapSeconds then
  pkgs.runCommand "firn-fleet-tick-start-budget" { } "touch $out"
else
  throw "fleet-tick.service must start within at least ${toString budget.swapSeconds} s (one north runtime deploy deadline of ${toString budget.runtimeDeployDeadlineSeconds} s plus the tick's ${toString budget.probeSeconds} s of probes), so a promotion's runtime swap cannot time its start out (north#1355); it has ${limit}"
