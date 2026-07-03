{ config, lib, pkgs, ... }:

{
  options.myConfig.modules.bench-shield.enable = lib.mkEnableOption "runtime CPU shield for timing-sensitive experiment runs";
  config = lib.mkIf config.myConfig.modules.bench-shield.enable {
    environment.systemPackages = [
      (pkgs.writeShellScriptBin "bench-shield" ''
        set -euo pipefail
        SYS_CORES="0-11"; BENCH_CORES="12-23"
        units="system.slice user.slice init.scope"
        case "''${1:-status}" in
          on)
            for u in $units; do sudo systemctl set-property --runtime "$u" AllowedCPUs=$SYS_CORES; done
            echo "shield ON — everything else confined to $SYS_CORES."
            echo "run experiments with: taskset -c $BENCH_CORES <cmd>  (cores $BENCH_CORES are now exclusive)"
            ;;
          off)
            for u in $units; do sudo systemctl set-property --runtime "$u" AllowedCPUs=""; done
            echo "shield OFF — all cores shared again."
            ;;
          status)
            for u in $units; do printf '%-14s AllowedCPUs=%s\n' "$u" "$(systemctl show -p AllowedCPUs --value "$u")"; done
            ;;
          *) echo "usage: bench-shield on|off|status" >&2; exit 2 ;;
        esac

      '')
    ];
  };
}
