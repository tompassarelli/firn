{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.myConfig.modules.farm-runners;
  username = config.myConfig.modules.users.username;
  homeDir = config.myConfig.modules.users.homeDir;
  host = config.networking.hostName;
  podman = "${config.virtualisation.podman.package}/bin/podman";
  stateDir = "${homeDir}/.local/state/farm-runners";
  slice = "agent-capacity-farm.slice";
  containerfile = ''
    FROM ghcr.io/actions/actions-runner:${cfg.runnerVersion}
    USER root
    RUN apt-get update -q && DEBIAN_FRONTEND=noninteractive apt-get install -yq --no-install-recommends ${lib.concatStringsSep " " cfg.aptPackages} && rm -rf /var/lib/apt/lists/*
    USER runner
  '';
  image = "localhost/farm-runner:${cfg.runnerVersion}-${
    builtins.substring 0 12 (builtins.hashString "sha256" containerfile)
  }";
  names = lib.concatLists (
    lib.mapAttrsToList (repo: count: map (i: "${repo}-${toString i}") (lib.range 1 count)) cfg.repos
  );
  credentials = ".runner .credentials .credentials_rsaparams";
  network = lib.optionalString (
    cfg.egressInterface != null
  ) " --network pasta:--outbound-if4,${cfg.egressInterface}";
  buildImage = pkgs.writeShellScript "farm-runner-image" ''
    ${podman} image exists ${image} || ${podman} build --cgroup-parent ${slice} -t ${image} -f ${pkgs.writeText "farm-runner.Containerfile" containerfile} ${pkgs.emptyDirectory}
  '';
  register = pkgs.writeShellApplication {
    name = "farm-runner-register";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.systemd
    ];
    text = ''
      usage() { echo "usage: farm-runner-register REPO-N < registration-token (one of: ${lib.concatStringsSep " " names})" >&2; exit 2; }
      [ $# -eq 1 ] || usage
      name=$1
      runners=" ${lib.concatStringsSep " " names} "
      case "$runners" in *" $name "*) ;; *) usage ;; esac
      repo=''${name%-*}
      IFS= read -r token
      [ -n "$token" ] || { echo "farm-runner-register: no registration token on stdin" >&2; exit 2; }
      systemctl --user start farm-runner-image.service
      dir=${stateDir}/$name
      mkdir -p "$dir" && chmod 700 "$dir"
      ${podman} run --rm -i --cgroup-parent ${slice} -v "$dir:/state" ${image} bash -c \
        'read -r t && ./config.sh --unattended --replace --disableupdate --url "$0" --token "$t" --name "$1" --labels "$2" --work _work >/dev/null && sudo cp ${credentials} /state/' \
        "https://github.com/${cfg.owner}/$repo" "${host}-$name" "${lib.concatStringsSep "," cfg.labels}" <<<"$token"
      systemctl --user restart "farm-runner-$name.service"
    '';
  };
  runnerUnit = name: {
    Unit = {
      Description = "Farm GitHub runner ${host}-${name} (${lib.concatStringsSep "," cfg.labels})";
      Requires = [ "farm-runner-image.service" ];
      After = [ "farm-runner-image.service" ];
      ConditionPathExists = "${stateDir}/${name}/.runner";
    };
    Service = {
      Slice = slice;
      Environment = "PATH=/run/wrappers/bin:/run/current-system/sw/bin";
      ExecStart = "${podman} run --rm --name farm-${name} --cgroup-parent ${slice}${network} --cpus ${toString cfg.cpus} --memory ${cfg.memory} -v ${stateDir}/${name}:/state:ro ${image} bash -c 'sudo install -o runner -m 600 -t . ${
        lib.concatMapStringsSep " " (f: "/state/${f}") (lib.splitString " " credentials)
      } && exec nice -n 19 ./run.sh'";
      ExecStop = "-${podman} stop -t 20 farm-${name}";
      Restart = "always";
      RestartSec = 10;
    };
    Install.WantedBy = [ "default.target" ];
  };
in
{
  options.myConfig.modules.farm-runners = {
    enable = lib.mkEnableOption "always-on self-hosted GitHub Actions farm runners in rootless Podman, registered from a machine that can mint registration tokens";
    owner = lib.mkOption {
      type = lib.types.str;
      description = "GitHub owner of the repositories the runners serve";
    };
    repos = lib.mkOption {
      type = lib.types.attrsOf lib.types.ints.positive;
      default = { };
      description = "runner count per repository name under owner";
    };
    labels = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "farm-big" ];
      description = "labels each runner registers with besides self-hosted, Linux and X64";
    };
    runnerVersion = lib.mkOption {
      type = lib.types.str;
      default = "2.338.0";
      description = "actions-runner image version";
    };
    aptPackages = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "build-essential"
        "imagemagick"
        "libstorm-dev"
        "ripgrep"
        "unzip"
        "curl"
        "jq"
        "git"
        "ca-certificates"
      ];
      description = "Ubuntu packages added to the runner image";
    };
    cpus = lib.mkOption {
      type = lib.types.ints.positive;
      default = 4;
      description = "CPU limit per runner container";
    };
    memory = lib.mkOption {
      type = lib.types.str;
      default = "8g";
      description = "memory limit per runner container";
    };
    egressInterface = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "enp5s0";
      description = "host interface every runner container's IPv4 traffic leaves by, so jobs reach the internet but no tunnel or private network such as wg-nexus; null routes them like any host process";
    };
    memoryMax = lib.mkOption {
      type = lib.types.str;
      default = "50%";
      description = "memory limit of the slice holding every runner, so jobs never take the host's working memory";
    };
  };
  config = lib.mkIf cfg.enable {
    virtualisation.podman.enable = true;
    environment.systemPackages = [ register ];
    home-manager.users.${username} = _: {
      systemd.user = {
        slices.agent-capacity-farm = {
          Unit.Description = "Farm runner containers inside the agent capacity slice at idle CPU and IO weight, so interactive work and game clients always win";
          Slice = {
            CPUWeight = "idle";
            IOWeight = 1;
            MemoryMax = cfg.memoryMax;
          };
        };
        services = {
          farm-runner-image = {
            Unit.Description = "Build the farm runner image ${image}";
            Service = {
              Type = "oneshot";
              RemainAfterExit = true;
              Environment = "PATH=/run/wrappers/bin:/run/current-system/sw/bin";
              ExecStart = "${buildImage}";
              TimeoutStartSec = "20min";
            };
          };
        }
        // lib.listToAttrs (map (name: lib.nameValuePair "farm-runner-${name}" (runnerUnit name)) names);
      };
    };
  };
}
