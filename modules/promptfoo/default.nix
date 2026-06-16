{ config, lib, pkgs, ... }:

{
  options.myConfig.modules.promptfoo.enable = lib.mkEnableOption "promptfoo — local, MIT-licensed LLM eval runner (no lock-in)";
  config = lib.mkIf config.myConfig.modules.promptfoo.enable {
    environment.systemPackages = [ pkgs.promptfoo ];
  };
}
