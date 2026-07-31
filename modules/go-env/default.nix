{ config, lib, pkgs, ... }:

{
  options.myConfig.modules.go-env.enable = lib.mkEnableOption "XDG paths for the Go toolchain";
  config = lib.mkIf config.myConfig.modules.go-env.enable {
    environment.sessionVariables = {
      GOPATH = "$HOME/.local/share/go";
      GOMODCACHE = "$HOME/.cache/go/mod";
      GOBIN = "$HOME/.local/bin";
    };
  };
}
