{ config, lib, pkgs, inputs, ... }:

{
  options.myConfig.modules.lodestar.enable = lib.mkEnableOption "Lodestar (life app) CLI + MCP server on PATH";
  config = lib.mkIf config.myConfig.modules.lodestar.enable {
    environment.systemPackages = [ inputs.lodestar.packages."${pkgs.stdenv.hostPlatform.system}".default ];
  };
}
