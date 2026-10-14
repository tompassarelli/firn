{ config, lib, ... }:
let
  cfg = config.myConfig.modules.go-env;
in
{
  config = lib.mkIf cfg.enable {
    environment.sessionVariables = {
      GOBIN = "$HOME/.local/bin";
      GOMODCACHE = "$HOME/.cache/go/mod";
      GOPATH = "$HOME/.local/share/go";
    };
  };
  options.myConfig.modules.go-env.enable = lib.mkEnableOption "XDG paths for the Go toolchain";
}
