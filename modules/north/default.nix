{ config, lib, pkgs, inputs, ... }:

{
  options.myConfig.modules.north.enable = lib.mkEnableOption "North (life app) CLI + MCP server on PATH";
  config = lib.mkIf config.myConfig.modules.north.enable {
    environment.systemPackages = [ inputs.tern.packages."${pkgs.stdenv.hostPlatform.system}".default ];
  };
}
