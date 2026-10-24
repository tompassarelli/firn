{ config, lib, ... }:
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
  };
  config = lib.mkIf cfg.enable {
    environment.sessionVariables.WLR_RENDER_DRM_DEVICE = cfg.renderNode;
  };
}
