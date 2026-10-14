{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.discord;
in
{
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.discord ]; };
  options.myConfig.modules.discord.enable = lib.mkEnableOption "Discord chat client";
}
