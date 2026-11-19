{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.wowup;
  pname = "wowup-cf";
  version = "2.25.5";
  src = pkgs.fetchurl {
    url = "https://github.com/WowUp/WowUp.CF/releases/download/v${version}/WowUp-CF-${version}.AppImage";
    hash = "sha512-1ktEGwO6row7IacebDZd8VhxPWAayfDYJdEYyxngyTfwameL4JrFd2rRAi5O9BcG03ZLUcaELK1SOTHwfe9J7A==";
  };
  contents = pkgs.appimageTools.extractType2 { inherit pname version src; };
  wowup = pkgs.appimageTools.wrapType2 {
    inherit pname version src;
    extraInstallCommands = ''
      install -m 444 -D ${contents}/${pname}.desktop -t $out/share/applications
      substituteInPlace $out/share/applications/${pname}.desktop --replace-fail 'Exec=AppRun' 'Exec=${pname}'
      cp -r ${contents}/usr/share/icons $out/share
    '';
    inherit (pkgs.wowup-cf) meta;
  };
in
{
  options.myConfig.modules.wowup.enable = lib.mkEnableOption "WowUp-CF addon manager";
  config = lib.mkIf cfg.enable { environment.systemPackages = [ wowup ]; };
}
