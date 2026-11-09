{
  config,
  lib,
  pkgs,
  unitPath,
  ...
}:

let
  cfg = config.myConfig.modules.north-land;
  homeDir = config.myConfig.modules.users.homeDir;
  username = config.myConfig.modules.users.username;
  description = "north-land: the lander, which checks each repository's queued lane tickets as one candidate and lands them on that repository's main";
  landerRuntime = "${homeDir}/.local/state/north/lander";
  unit = label: serves: {
    Unit.Description = "${description} (${label})";
    Service = {
      Slice = "agent.slice";
      Type = "simple";
      Restart = "always";
      RestartSec = "5s";
      TimeoutStopSec = "15s";
      Nice = 5;
      Environment = [
        "PATH=${unitPath}:${
          lib.makeBinPath [
            pkgs.bash
            pkgs.bun
            pkgs.cargo-deny
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
        "NORTH_RUNTIME_LINK=${landerRuntime}"
        "NORTH_LAND_RUNNER_SLICE=agent.slice"
      ];
      ExecStart = "${landerRuntime}/tree/bin/north land serve ${serves}";
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
        "battlecraft"
        "clause"
        "glide"
        "makgora"
        "makgora-client"
        "nixos-config"
        "north"
        "padbridge"
        "slippi-launcher"
        "south"
        "wisp"
      ];
      description = ''
        Repositories under ~/code/<name>/main that each get their own lander unit north-land@<name>, so an error in one repository's loop never delays another's.
        Every other repository with a land queue on this host is served by north-land-rest (north land serve --all, which skips the repositories listed here),
        so no queue waits without a server and a private repository never has to be named in this public file; north land route refuses a lane on a host that declares neither.
        Every unit runs the runtime ~/.local/state/north/lander points at, which moves only through north land promote, never with main.
      '';
    };
  };
  config = lib.mkIf cfg.enable {
    home-manager.users.${username} = _: {
      systemd.user.services =
        lib.listToAttrs (
          map (
            repo: lib.nameValuePair "north-land@${repo}" (unit repo "--repo ${homeDir}/code/${repo}/main")
          ) cfg.repositories
        )
        // {
          north-land-rest = unit "every other queue" "--all";
        };
    };
  };
}
