{
  config,
  lib,
  pkgs,
  northBin,
  ...
}:

let
  cfg = config.myConfig.modules.north-land;
  homeDir = config.myConfig.modules.users.homeDir;
  username = config.myConfig.modules.users.username;
  description = "north-land: the lander, which checks each repository's queued lane tickets as one candidate and lands them on that repository's main";
  landerRuntime = "${homeDir}/.local/state/north/lander";
  unit = repo: {
    Unit.Description = "${description} (${repo})";
    Service = {
      Type = "simple";
      Restart = "always";
      RestartSec = "5s";
      TimeoutStopSec = "15s";
      Nice = 5;
      Environment = [
        "PATH=/run/wrappers/bin:/run/current-system/sw/bin:${homeDir}/.local/bin:${northBin}:${homeDir}/.local/share/firn/bin:${
          lib.makeBinPath [
            pkgs.bash
            pkgs.bun
            pkgs.coreutils
            pkgs.git
            pkgs.gnutar
            pkgs.nix
            pkgs.openssh
            pkgs.rsync
            pkgs.systemd
            pkgs.util-linux
          ]
        }"
        "SAFE_PUSH_LAND_RUNNER="
        "NORTH_RUNTIME_LINK=${landerRuntime}"
      ];
      ExecStart = "${landerRuntime}/tree/bin/north land serve --depth 4 --repo ${homeDir}/code/${repo}/main";
    };
    Install.WantedBy = [ "default.target" ];
  };
in
{
  options.myConfig.modules.north-land = {
    enable = lib.mkEnableOption description;
    repositories = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "north"
        "makgora"
        "nixos-config"
        "padbridge"
        "south"
        "wisp"
      ];
      description = ''
        Repositories under ~/code/<name>/main that each get their own lander unit north-land@<name>, so an error in one repository's loop never delays another's.
        Every unit runs the runtime ~/.local/state/north/lander points at, which moves only through north land promote, never with main.
      '';
    };
  };
  config = lib.mkIf cfg.enable {
    home-manager.users.${username} = _: {
      systemd.user.services = lib.listToAttrs (
        map (repo: lib.nameValuePair "north-land@${repo}" (unit repo)) cfg.repositories
      );
    };
  };
}
