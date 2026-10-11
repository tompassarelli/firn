{ config, lib, ... }:

{
  config = lib.mkIf config.myConfig.modules.go-env.enable {
    "environment" = {
      "sessionVariables" = {
        "GOBIN" = "$HOME/.local/bin";
        "GOMODCACHE" = "$HOME/.cache/go/mod";
        "GOPATH" = "$HOME/.local/share/go";
      };
    };
  };
  options."myConfig"."modules"."go-env"."enable" = lib.mkEnableOption "XDG paths for the Go toolchain";
}
