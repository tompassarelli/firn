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
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.forgejo-cli ]; };
  options.myConfig.modules.forgejo-cli.enable =
    lib.mkEnableOption "Forgejo CLI for repo / issue / CI ops against codeberg + other Forgejo instances";
}
