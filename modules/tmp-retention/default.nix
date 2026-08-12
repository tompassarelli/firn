{ config, lib, pkgs, ... }:

{
  options.myConfig.modules.tmp-retention.enable = lib.mkEnableOption "mtime-pinned /tmp and /var/tmp retention (systemd-tmpfiles age-by override)";
  config = lib.mkIf config.myConfig.modules.tmp-retention.enable {
    systemd.tmpfiles.rules = [ "q /tmp 1777 root root mM:7d" "q /var/tmp 1777 root root mM:30d" ];
  };
}
