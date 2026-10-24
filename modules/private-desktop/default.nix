{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.private-desktop;
in
{
  options.myConfig.modules.private-desktop = {
    enable = lib.mkEnableOption "a chosen GPU render node for headless private desktops";
    renderNode = lib.mkOption {
      type = lib.types.str;
      example = "/dev/dri/by-path/pci-0000:01:00.0-render";
      description = "Render node, or a stable link to one, that private desktops render on.";
    };
    reserveHostDisplay = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Hold X display :0 on a host with no graphical session, because private desktops refuse :0 as the normal desktop's display.";
    };
  };
  config = lib.mkIf cfg.enable {
    environment.sessionVariables.WLR_RENDER_DRM_DEVICE = cfg.renderNode;
    systemd.tmpfiles.rules = lib.mkIf cfg.reserveHostDisplay [ "x /tmp/.X0-lock" ];
    systemd.services.private-desktop-host-display = lib.mkIf cfg.reserveHostDisplay {
      description = "Hold X display :0 for the normal desktop this host does not run";
      wantedBy = [ "multi-user.target" ];
      after = [ "systemd-tmpfiles-setup.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${pkgs.coreutils}/bin/install -m 0444 /dev/null /tmp/.X0-lock";
      };
    };
  };
}
