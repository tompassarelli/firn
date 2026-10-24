{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.myConfig.modules.farm-runners;
  inherit (cfg) user;
  uid = toString cfg.uid;
  homeDir = "/var/lib/${user}";
  host = config.networking.hostName;
  podman = "${config.virtualisation.podman.package}/bin/podman";
  stateDir = "${homeDir}/runners";
  containerfile = ''
    FROM ghcr.io/actions/actions-runner:${cfg.runnerVersion}
    USER root
    RUN apt-get update -q && DEBIAN_FRONTEND=noninteractive apt-get install -yq --no-install-recommends ${lib.concatStringsSep " " cfg.aptPackages} && DEBIAN_FRONTEND=noninteractive SUDO_FORCE_REMOVE=yes apt-get purge -yq sudo && rm -rf /var/lib/apt/lists/*
    USER runner
  '';
  image = "localhost/farm-runner:${cfg.runnerVersion}-${
    builtins.substring 0 12 (builtins.hashString "sha256" containerfile)
  }";
  names = lib.concatLists (
    lib.mapAttrsToList (repo: count: map (i: "${repo}-${toString i}") (lib.range 1 count)) cfg.repos
  );
  credentials = ".runner .credentials .credentials_rsaparams";
  confine = "--cap-drop all --security-opt no-new-privileges";
  buildImage = pkgs.writeShellScript "farm-runner-image" ''
    ${podman} image exists ${image} || ${podman} build -t ${image} -f ${pkgs.writeText "farm-runner.Containerfile" containerfile} ${pkgs.emptyDirectory}
  '';
  register = pkgs.writeShellApplication {
    name = "farm-runner-register";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.systemd
      pkgs.util-linux
    ];
    text = ''
      usage() { echo "usage: farm-runner-register REPO-N < registration-token, as root (one of: ${lib.concatStringsSep " " names})" >&2; exit 2; }
      [ $# -eq 1 ] || usage
      [ "$(id -u)" -eq 0 ] || usage
      name=$1
      runners=" ${lib.concatStringsSep " " names} "
      case "$runners" in *" $name "*) ;; *) usage ;; esac
      repo=''${name%-*}
      IFS= read -r token
      [ -n "$token" ] || { echo "farm-runner-register: no registration token on stdin" >&2; exit 2; }
      as_farm() { runuser -u ${user} -- env HOME=${homeDir} XDG_RUNTIME_DIR=/run/user/${uid} DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/${uid}/bus "$@"; }
      as_farm systemctl --user start farm-runner-image.service
      dir=${stateDir}/$name
      as_farm mkdir -p "$dir"
      as_farm chmod 700 "$dir"
      as_farm ${podman} run --rm -i ${confine} -v "$dir:/state:U" ${image} bash -c \
        'read -r t && ./config.sh --unattended --replace --disableupdate --url "$0" --token "$t" --name "$1" --labels "$2" --work _work >/dev/null && cp ${credentials} /state/' \
        "https://github.com/${cfg.owner}/$repo" "${host}-$name" "${lib.concatStringsSep "," cfg.labels}" <<<"$token"
      as_farm systemctl --user restart "farm-runner-$name.service"
    '';
  };
  runnerUnit = name: {
    Unit = {
      Description = "Farm GitHub runner ${host}-${name} (${lib.concatStringsSep "," cfg.labels}), one job per container";
      Requires = [ "farm-runner-image.service" ];
      After = [ "farm-runner-image.service" ];
      ConditionPathExists = "${stateDir}/${name}/.runner";
    };
    Service = {
      Environment = "PATH=/run/wrappers/bin:/run/current-system/sw/bin";
      ExecStart = "${podman} run --rm --name farm-${name} ${confine} --cpus ${toString cfg.cpus} --memory ${cfg.memory} -v ${stateDir}/${name}:/state:ro,U ${image} bash -c 'cp ${
        lib.concatMapStringsSep " " (f: "/state/${f}") (lib.splitString " " credentials)
      } . && exec nice -n 19 ./run.sh --once'";
      ExecStop = "-${podman} stop -t 20 farm-${name}";
      Restart = "always";
      RestartSec = 5;
    };
    Install.WantedBy = [ "default.target" ];
  };
in
{
  options.myConfig.modules.farm-runners = {
    enable = lib.mkEnableOption "always-on self-hosted GitHub Actions farm runners in rootless Podman under a dedicated unprivileged user, each container taking one job, registered from a machine that can mint registration tokens";
    owner = lib.mkOption {
      type = lib.types.str;
      description = "GitHub owner of the repositories the runners serve";
    };
    repos = lib.mkOption {
      type = lib.types.attrsOf lib.types.ints.positive;
      default = { };
      description = "runner count per repository name under owner";
    };
    user = lib.mkOption {
      type = lib.types.str;
      default = "farm";
      description = "system user that owns the runner containers, their registrations and their user manager; it holds no other credentials";
    };
    uid = lib.mkOption {
      type = lib.types.ints.positive;
      default = 900;
      description = "fixed uid and gid of the runner user, so its user slice and the egress filter can name it";
    };
    subIdStart = lib.mkOption {
      type = lib.types.ints.positive;
      default = 165536;
      description = "first subordinate uid and gid of the runner user's 65536-id range, clear of the login user's range";
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
      description = "Ubuntu packages added to the runner image, which ships without sudo";
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
      type = lib.types.str;
      example = "enp5s0";
      description = "the only host interface the runner user's traffic may leave by, enforced by uid in nftables, so jobs reach the internet but no tunnel, private network or host-local service";
    };
    egressPorts = lib.mkOption {
      type = lib.types.listOf lib.types.port;
      default = [
        80
        443
      ];
      description = "TCP ports runner jobs may open connections to through egressInterface; everything else the runner user sends, apart from DNS to the local resolver, is refused";
    };
    egressRate = lib.mkOption {
      type = lib.types.str;
      default = "200/second burst 2000 packets";
      description = "nftables limit on new outbound connections from the runner user, far above any build's fetches and below a scan";
    };
    memoryMax = lib.mkOption {
      type = lib.types.str;
      default = "50%";
      description = "memory limit of the runner user's slice, so jobs never take the host's working memory";
    };
  };
  config = lib.mkIf cfg.enable {
    virtualisation.podman.enable = true;
    environment.systemPackages = [ register ];
    users.groups.${user}.gid = cfg.uid;
    users.users.${user} = {
      inherit (cfg) uid;
      isSystemUser = true;
      group = user;
      home = homeDir;
      createHome = true;
      homeMode = "700";
      linger = true;
      subUidRanges = [
        {
          startUid = cfg.subIdStart;
          count = 65536;
        }
      ];
      subGidRanges = [
        {
          startGid = cfg.subIdStart;
          count = 65536;
        }
      ];
    };
    systemd.slices."user-${uid}" = {
      overrideStrategy = "asDropin";
      sliceConfig = {
        CPUWeight = "idle";
        IOWeight = 1;
        MemoryMax = cfg.memoryMax;
      };
    };
    networking.nftables.tables.farm-egress = {
      family = "inet";
      content = ''
        chain output {
          type filter hook output priority filter; policy accept;
          meta skuid ${uid} jump runner
        }
        chain runner {
          ct state established,related accept
          ip daddr { 127.0.0.53, 127.0.0.54 } meta l4proto { tcp, udp } th dport 53 accept
          oifname "${cfg.egressInterface}" tcp dport { ${
            lib.concatMapStringsSep ", " toString cfg.egressPorts
          } } ct state new limit rate ${cfg.egressRate} accept
          counter reject
        }
      '';
    };
    home-manager.users.${user} = _: {
      home.stateVersion = config.system.stateVersion;
      systemd.user.services = {
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
}
