{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.sccache;
  sccache = "${pkgs.sccache}/bin/sccache";
  laneLauncher = pkgs.writeShellScript "sccache-lane" ''
    if [[ $PWD =~ ^(${config.myConfig.modules.users.homeDir}/code/[^/]+/(worktrees/[^/]+|main))(/|$) ]]; then
      export SCCACHE_BASEDIRS=''${BASH_REMATCH[1]}
      export SCCACHE_SERVER_PORT=$((20000 + $(printf %s "$SCCACHE_BASEDIRS" | ${pkgs.coreutils}/bin/cksum | ${pkgs.coreutils}/bin/cut -d' ' -f1) % 20000))
    fi
    exec ${sccache} "$@"
  '';
in
{
  options.myConfig.modules.sccache = {
    enable = lib.mkEnableOption "sccache as the Rust compiler wrapper and CMake compiler launcher in every user session";
    cacheDir = lib.mkOption {
      type = lib.types.str;
      default = "$HOME/.cache/sccache";
      description = "Local disk cache directory shared by all checkouts of the user";
    };
    cacheSize = lib.mkOption {
      type = lib.types.str;
      default = "30G";
      description = "Size cap of the local cache, in sccache's SCCACHE_CACHE_SIZE form";
    };
  };
  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ pkgs.sccache ];
    environment.sessionVariables = {
      RUSTC_WRAPPER = sccache;
      SCCACHE_DIR = cfg.cacheDir;
      SCCACHE_CACHE_SIZE = cfg.cacheSize;
      SCCACHE_BASEDIRS = "$HOME/code";
      CMAKE_C_COMPILER_LAUNCHER = "${laneLauncher}";
      CMAKE_CXX_COMPILER_LAUNCHER = "${laneLauncher}";
    };
  };
}
