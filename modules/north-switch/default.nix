{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.myConfig.modules.north-switch;
  username = config.myConfig.modules.users.username;
  lines = kind: map (value: "${kind} ${value}") cfg.${kind};
in
{
  options.myConfig.modules.north-switch = {
    enable =
      lib.mkEnableOption "north-switch: `north fleet off` and `north fleet on` from the host's own closure, so they answer while north's runtime is missing or broken"
      // {
        default =
          config.myConfig.modules.north-runtime-follow.enable || config.myConfig.modules.bash.enable;
      };
    host = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "whiterabbit"
        "nexus"
        "gex45"
        "cpx62"
        "cpx62b"
      ];
      description = "The fleet hosts `north fleet off` reaches over ssh besides this one.";
    };
    unit = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "north-*"
        "fleet-*"
        "build-time.*"
        "coverage-map-refresh.*"
        "firn-delivery-liveness.*"
        "firn-host-follow.*"
        "lane-gc.*"
        "lease-reaper.*"
        "mutant-sweep.*"
        "proxy-terminal-watch.*"
      ];
      description = "Globs of the user units that are the fleet's: `north fleet off` stops the running ones and `north fleet on` starts them again.";
    };
    keep = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "north-gh-broker.*" ];
      description = "Globs of fleet-named user units `north fleet off` never stops: the credential broker the owner's own pushes use.";
    };
  };
  config = lib.mkIf cfg.enable {
    home-manager.users.${username} = _: {
      home.packages = [ pkgs.north-switch ];
      xdg.configFile."north/fleet-units".text =
        lib.concatStringsSep "\n" (lines "host" ++ lines "unit" ++ lines "keep") + "\n";
    };
  };
}
