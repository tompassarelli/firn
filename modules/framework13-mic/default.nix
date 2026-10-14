{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.framework13-mic;
in
{
  options.myConfig.modules.framework13-mic.enable =
    lib.mkEnableOption "Framework 13 AMD AI 300 mic fix + firn-mic CLI (forces UCM profile that exposes the actual internal mic; see `firn-mic doctor`)";
  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      (pkgs.writeShellApplication {
        name = "firn-mic";
        runtimeInputs = [
          pkgs.wireplumber
          pkgs.pipewire
          pkgs.jq
          pkgs.python3
          pkgs.coreutils
          pkgs.gnugrep
          pkgs.gawk
          pkgs.gnused
        ];
        text = builtins.readFile ./firn-mic;
      })
    ];
    home-manager.users.${config.myConfig.modules.users.username}.systemd.user.services.firn-mic-ensure =
      {
        Install.WantedBy = [ "pipewire.service" ];
        Service = {
          ExecStart = "${
            pkgs.writeShellApplication {
              name = "firn-mic";
              runtimeInputs = [
                pkgs.wireplumber
                pkgs.pipewire
                pkgs.jq
                pkgs.python3
                pkgs.coreutils
                pkgs.gnugrep
                pkgs.gawk
                pkgs.gnused
              ];
              text = builtins.readFile ./firn-mic;
            }
          }/bin/firn-mic --quiet";
          ExecStartPre = "${pkgs.coreutils}/bin/sleep 2";
          RemainAfterExit = true;
          Type = "oneshot";
        };
        Unit = {
          After = [
            "pipewire.service"
            "wireplumber.service"
          ];
          Description = "Pin Framework 13 mic profile and default source";
          PartOf = [ "pipewire.service" ];
        };
      };
    services.pipewire.wireplumber.extraConfig."51-framework13-mic"."monitor.alsa.rules" = [
      {
        actions.update-props."device.profile" = "HiFi (Mic1, Mic2, Speaker)";
        matches = [
          { "device.name" = "alsa_card.pci-0000_c1_00.6"; }
        ];
      }
    ];
    systemd.services.firn-mic-alsa-init = {
      after = [ "sound.target" ];
      description = "Disable Internal Mic Boost on Framework 13 ALC285";
      path = [
        pkgs.alsa-utils
        pkgs.gnugrep
        pkgs.gnused
        pkgs.coreutils
      ];
      script = ''
        set -eu
        # Find the card index of the ALC285 codec (stable across reboots).
        card=$(grep -l 'Realtek ALC285' /proc/asound/card*/codec* 2>/dev/null \
                | sed -nE 's|.*/card([0-9]+)/.*|\1|p' | head -1)
        if [ -z "$card" ]; then
          echo "firn-mic-alsa-init: ALC285 codec not found, skipping" >&2
          exit 0
        fi
        amixer -c "$card" set 'Internal Mic Boost' 0 >/dev/null
        echo "firn-mic-alsa-init: card$card 'Internal Mic Boost' = 0 dB"

      '';
      serviceConfig = {
        RemainAfterExit = true;
        Type = "oneshot";
      };
      wantedBy = [ "multi-user.target" ];
    };
  };
}
