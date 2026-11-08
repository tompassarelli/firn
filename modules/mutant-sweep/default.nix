{
  config,
  lib,
  jobRun,
  northBin,
  unitPath,
  pkgs,
  ...
}:

let
  cfg = config.myConfig.modules.mutant-sweep;
  homeDir = config.myConfig.modules.users.homeDir;
  username = config.myConfig.modules.users.username;
  checkout = "${homeDir}/.local/state/north/mutant-sweep/north";
  description = "Monthly mutation and retirement sweep: mutate north's product code on a build host, join the kills with the catch evidence and add one box on north#635 listing the tests that earn nothing";
in
{
  options.myConfig.modules.mutant-sweep.enable = lib.mkEnableOption description;
  config = lib.mkIf cfg.enable {
    home-manager.users.${username} = _: {
      systemd.user = {
        services.mutant-sweep = {
          Unit = {
            Description = description;
            OnFailure = [ "update-notify@%n.service" ];
            X-SwitchMethod = "keep-old";
          };
          Service = {
            Slice = "agent.slice";
            Type = "oneshot";
            Nice = 10;
            TimeoutStartSec = "7h";
            Environment = [
              "PATH=${unitPath}:${lib.makeBinPath [ pkgs.git ]}"
            ];
            ExecStartPre = "${pkgs.bash}/bin/bash -c 'test -d ${checkout} || ${pkgs.git}/bin/git clone --quiet https://github.com/tompassarelli/north.git ${checkout}; ${pkgs.git}/bin/git -C ${checkout} fetch --quiet origin main && ${pkgs.git}/bin/git -C ${checkout} checkout --quiet --detach FETCH_HEAD'";
            ExecStart = jobRun "mutant-sweep" "${northBin}/north test mutant sweep --repo ${checkout} --host gex45 --mutants 40 --timeout 3600 --issue north#635";
          };
        };
        timers.mutant-sweep = {
          Unit.Description = description;
          Timer = {
            OnCalendar = "monthly";
            RandomizedDelaySec = "1h";
            Persistent = true;
          };
          Install.WantedBy = [ "timers.target" ];
        };
      };
    };
  };
}
