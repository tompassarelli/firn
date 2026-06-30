{ config, lib, pkgs, inputs, ... }:

{
  options.myConfig.modules.tern.enable = lib.mkEnableOption "Tern (life app) CLI + MCP server on PATH";
  config = lib.mkIf config.myConfig.modules.tern.enable {
    environment.systemPackages = [ inputs.tern.packages."${pkgs.stdenv.hostPlatform.system}".default ];
  };
}
