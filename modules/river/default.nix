{ config, lib, pkgs, ... }:

let
  zig = pkgs.zig_0_16;
  rillDeps = pkgs.linkFarm "rill-zig-deps" [
    {
      name = "wayland-0.6.0-lQa1kqz8AQADQmdNJsNhLoNHcnEGEUjrOaPV-dtEnEmX";
      path = pkgs.fetchzip {
        url = "https://codeberg.org/ifreund/zig-wayland/archive/v0.6.0.tar.gz";
        hash = "sha256-3m/ITNhZUJ/5uD/Tqm+0uZSktGoYgWF5oldOqOCUkIE=";
      };
    }
    {
      name = "xkbcommon-0.4.0-VDqIe0i2AgDRsok2GpMFYJ8SVhQS10_PI2M_CnHXsJJZ";
      path = pkgs.fetchzip {
        url = "https://codeberg.org/ifreund/zig-xkbcommon/archive/v0.4.0.tar.gz";
        hash = "sha256-zQkmP/cuhAtjOLqYS5D15khKzpqyhbyZ0TD6/8jOkqE=";
      };
    }
  ];
  rill = pkgs.stdenv.mkDerivation {
    pname = "rill";
    version = "0.6.0";
    src = pkgs.fetchFromCodeberg {
      owner = "lzj15";
      repo = "rill";
      tag = "0.6.0";
      hash = "sha256-32DtBy/zgic2iKGrs8WRr7bzv640ACsI8KmzENtcLtA=";
    };
    strictDeps = true;
    nativeBuildInputs = [ pkgs.pkg-config pkgs.wayland-scanner zig ];
    buildInputs = [
      pkgs.wayland
      pkgs.wayland-protocols
      pkgs.wayland-scanner
      pkgs.libxkbcommon
    ];
    zigBuildFlags = [ "--system" "${rillDeps}" ];
    meta = {
      description = "Minimalist scrolling window manager for river (river-window-management-v1)";
      homepage = "https://codeberg.org/lzj15/rill";
      license = lib.licenses.mit;
      mainProgram = "rill";
      platforms = lib.platforms.linux;
    };
  };
in
{
  options.myConfig.modules.river.enable = lib.mkEnableOption "Enable river 0.4 Wayland compositor (pluggable-WM lane; opt-in)";
  config = lib.mkIf config.myConfig.modules.river.enable {
    programs.river-classic.enable = true;
    programs.river-classic.package = pkgs.unstable.river;
    programs.river-classic.extraPackages = [ rill ];
    programs.river-classic.xwayland.enable = true;
    environment.sessionVariables.NIXOS_OZONE_WL = "1";
  };
}
