{ config, lib, pkgs, inputs, ... }:

{
  options.myConfig.modules.beagle.enable = lib.mkEnableOption "beagle compiler + CLI suite (racket-pinned, hermetic)";
  config = lib.mkIf config.myConfig.modules.beagle.enable {
    environment.systemPackages = [ inputs.beagle.packages."${pkgs.stdenv.hostPlatform.system}".default ];
  };
}
