{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.myConfig.modules.framework;
  username = config.myConfig.modules.users.username;
  lidDrain = pkgs.writeShellApplication {
    name = "lid-drain-hook";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.util-linux
      pkgs.openssh
    ];
    runtimeEnv.DRAIN_USER = username;
    text = ''
      phase=''${1:-}
      action=''${2:-}
      leg=''${SYSTEMD_SLEEP_ACTION:-}
      ac=''${LID_DRAIN_AC_ONLINE:-/sys/class/power_supply/ACAD/online}
      log() { logger -t lid-drain -- "$*"; }
      [ "$phase" = pre ] || exit 0
      case "$action" in
        suspend|hibernate|hybrid-sleep|suspend-then-hibernate) ;;
        *) exit 0 ;;
      esac
      if [ "$action" = suspend-then-hibernate ] && [ "$leg" = hibernate ]; then
        log "skip: hibernate leg of suspend-then-hibernate"
        exit 0
      fi
      online=$(cat "$ac" 2>/dev/null || echo unknown)
      if [ "$online" != 0 ]; then
        log "skip: action=$action ac_online=$online"
        exit 0
      fi
      rc=0
      out=$(runuser -u "$DRAIN_USER" -- timeout 5 ssh -o BatchMode=yes -o ConnectTimeout=5 nexus laptop drain lid 2>&1) || rc=$?
      out=$(printf '%s' "$out" | tr '\n' ' ' | cut -c1-200)
      if [ "$rc" = 0 ]; then
        log "drained: action=$action ssh=ok"
      else
        log "drain failed (failing open): action=$action rc=$rc output=$out"
      fi
      exit 0
    '';
  };
in
{
  config = lib.mkIf cfg.enable {
    boot.extraModprobeConfig = ''
      options mt7925_common disable_clc=1
      options mt7925e disable_aspm=1

    '';
    environment.etc."systemd/system-sleep/lid-drain".source = "${lidDrain}/bin/lid-drain-hook";
    systemd.sleep.settings.Sleep.HibernateDelaySec = "30min";
    services.logind.settings.Login = {
      HandleLidSwitch = "suspend-then-hibernate";
      HandleLidSwitchExternalPower = "ignore";
    };
  };
  options.myConfig.modules.framework.enable = lib.mkEnableOption "Framework Computer specific tools";
}
