{ config, lib, ... }:

{
  config = {
    "system" = {
      "stateVersion" = config.myConfig.modules.system.stateVersion;
    };
  };
  options."myConfig"."modules"."system"."stateVersion" = lib.mkOption {
    type = lib.types.str;
    description = "The NixOS state version. Set this to the NixOS version you originally\ninstalled (e.g., \"24.05\", \"25.05\"). Do NOT change this after initial\ninstall unless you know what you're doing.\n\nThis controls backwards compatibility for stateful data like database\nschemas, service data directories, etc.\n\n";
  };
}
