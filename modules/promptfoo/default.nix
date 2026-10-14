{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.promptfoo;
in
{
  config = lib.mkIf cfg.enable { environment.systemPackages = [ pkgs.promptfoo ]; };
  options.myConfig.modules.promptfoo.enable =
    lib.mkEnableOption "promptfoo — local, MIT-licensed LLM eval runner (no lock-in)";
}
