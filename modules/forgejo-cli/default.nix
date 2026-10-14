{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.forgejo-cli;
in
{
  options.myConfig.modules.forgejo-cli.enable =
    lib.mkEnableOption "Forgejo CLI for repo / issue / CI ops against codeberg + other Forgejo instances";
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.forgejo-cli ]; };
}
