{ config, lib, ... }:

{
  config.system.stateVersion = config.myConfig.modules.system.stateVersion;
  options.myConfig.modules.system.stateVersion = lib.mkOption {
    type = lib.types.str;
    description = ''
      The NixOS state version. Set this to the NixOS version you originally
      installed (e.g., "24.05", "25.05"). Do NOT change this after initial
      install unless you know what you're doing.

      This controls backwards compatibility for stateful data like database
      schemas, service data directories, etc.

    '';
  };
}
