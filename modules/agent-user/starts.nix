{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.myConfig.modules.agent-user;
  starts = cfg.localStarts;
  operator = config.myConfig.modules.users.username;
  unit = "north-agent-starts";
  requests = "/var/lib/${unit}";
  machinectl = "${config.systemd.package}/bin/machinectl";
  entry = pkgs.writeShellScript "north-agent-start" ''
    exec ${starts.package}/bin/north-agent-starts take --home ${cfg.home}
  '';
  checker = pkgs.writeShellScript "north-agent-starts-caller" ''
    set -eu
    pid=$1
    case $pid in "" | *[!0-9]*) exit 1 ;; esac
    started() { ${pkgs.gnused}/bin/sed 's/.*) //' "/proc/$pid/stat" | ${pkgs.coreutils}/bin/cut -d' ' -f20; }
    before=$(started)
    cgroup=$(${pkgs.coreutils}/bin/cat "/proc/$pid/cgroup")
    after=$(started)
    [ -n "$before" ] && [ "$before" = "$after" ] && [ "$cgroup" = "0::/system.slice/${unit}.service" ]
  '';
in
{
  options.myConfig.modules.agent-user.localStarts = {
    enable = lib.mkEnableOption "local agent starts: the ${unit} system unit, run as the operator outside every session scope, takes each start request the fleet tick writes into its state directory as fixed fields and opens a fixed entry as the agent through machined's host shell, which polkit admits for that unit's processes alone";
    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.north-agent-starts;
      description = "The north-agent-starts package, built into the store, that the unit and the entry run";
    };
    caller = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether the polkit rule checks the caller is the unit's own process; off only in the VM check that shows the rule is what refuses everyone else";
    };
  };
  config = lib.mkIf (cfg.enable && starts.enable) {
    boot.kernel.sysctl."kernel.yama.ptrace_scope" = lib.mkDefault 1;
    assertions = [
      {
        assertion = (config.boot.kernel.sysctl."kernel.yama.ptrace_scope" or 1) >= 1;
        message = "local agent starts need kernel.yama.ptrace_scope 1 or above, or any operator process could ptrace the starter and act as its unit";
      }
    ];
    security.polkit.extraConfig = ''
      polkit.addRule(function (action, subject) {
        if (action.id != "org.freedesktop.machine1.host-shell" || action.lookup("user") != "${cfg.name}") {
          return polkit.Result.NOT_HANDLED;
        }
        if (action.lookup("machine") == ".host" && action.lookup("program") == "${entry}" && action.lookup("command_line") == "${entry}"${lib.optionalString starts.caller " && subject.user == \"${operator}\" && subject.system_unit == \"${unit}.service\""}) {
          ${
            if starts.caller then
              ''
                try {
                  polkit.spawn(["${checker}", String(subject.pid)]);
                  return polkit.Result.YES;
                } catch (error) {
                  polkit.log("${unit}: refused caller " + subject.pid + ": " + error);
                }''
            else
              "return polkit.Result.YES;"
          }
        }
        return polkit.Result.NO;
      });
    '';
    systemd.services.${unit} = {
      description = "Start local agent sessions from the requests in ${requests}, each request read as fixed fields and handed to the agent only through machined's host shell";
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        User = operator;
        ExecStart = "${starts.package}/bin/north-agent-starts serve --requests ${requests} --agent ${cfg.name} --home ${cfg.home} --entry ${entry} --machinectl ${machinectl}";
        Restart = "always";
        RestartSec = 5;
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        StateDirectory = unit;
        StateDirectoryMode = "0700";
        PrivateTmp = true;
        PrivateNetwork = true;
        RestrictAddressFamilies = [ "AF_UNIX" ];
        UMask = "0077";
      };
    };
  };
}
