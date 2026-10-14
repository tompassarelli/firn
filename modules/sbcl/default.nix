{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.sbcl;
in
{
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.sbcl ]; };
  options.myConfig.modules.sbcl.enable = lib.mkEnableOption "Steel Bank Common Lisp compiler";
}
