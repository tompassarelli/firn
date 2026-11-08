{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.myConfig.modules.home-snapshots;
  homeDir = config.myConfig.modules.users.homeDir;
  snapshotDir = "${cfg.volume}/.snapshots";
  guard = pkgs.writeShellScript "home-snapshots-guard" ''
    for sub in ${lib.escapeShellArgs cfg.excludedSubvolumes}; do
      if ! ${pkgs.btrfs-progs}/bin/btrfs subvolume show "$sub" >/dev/null 2>&1; then
        echo "home-snapshots: $sub is not its own subvolume, so a snapshot would keep every file deleted from it for ${toString cfg.keepDays} days" >&2
        exit 1
      fi
    done
  '';
in
{
  options.myConfig.modules.home-snapshots = {
    enable = lib.mkEnableOption "home-snapshots: hourly read-only btrfs snapshots of the home volume kept 48 h, daily ones kept for keepDays";
    volume = lib.mkOption {
      type = lib.types.str;
      default = "/home";
      description = "mount point of the btrfs subvolume to snapshot";
    };
    keepDays = lib.mkOption {
      type = lib.types.ints.positive;
      default = 14;
      description = "days the daily snapshots are kept";
    };
    excludedSubvolumes = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "${homeDir}/.cache" ];
      description = "directories that must be nested subvolumes, which a snapshot leaves out, so cargo targets, sccache and build slots never pin freed disk; the snapshot service refuses to run while one is a plain directory";
    };
  };
  config = lib.mkIf cfg.enable {
    systemd.tmpfiles.rules = [ "v ${snapshotDir} 0700 root root -" ];
    services.btrbk.instances.home = {
      onCalendar = "hourly";
      settings = {
        snapshot_preserve_min = "latest";
        snapshot_preserve = "48h ${toString cfg.keepDays}d";
        snapshot_create = "always";
        timestamp_format = "long";
        snapshot_dir = ".snapshots";
        volume.${cfg.volume} = {
          subvolume."." = {
            snapshot_name = "home";
          };
        };
      };
    };
    systemd.services.btrbk-home.serviceConfig.ExecStartPre = "${guard}";
  };
}
