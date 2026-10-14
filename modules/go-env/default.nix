{ config, lib, ... }:
let
  cfg = config.myConfig.modules.go-env;
in
{
  options.myConfig.modules.go-env.enable = lib.mkEnableOption "XDG paths for the Go toolchain";
  config = lib.mkIf cfg.enable {
    environment.sessionVariables = {
      GOBIN = "$HOME/.local/bin";
      GOMODCACHE = "$HOME/.cache/go/mod";
      GOPATH = "$HOME/.local/share/go";
    };
  };
}
