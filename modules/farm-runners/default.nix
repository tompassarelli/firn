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
  stateMount = dir: "--userns keep-id:uid=1001,gid=1001 -v ${dir}:/state";
  limits = "--cpus ${toString cfg.cpus} --memory ${cfg.memory}";
  jit = cfg.jitTokenFile != null;
  nft = config.networking.nftables.enable;
  pauseMarker = "/run/farm-runners-paused";
  gate = cfg.gameGate.user;
  gateUser = if gate == null then null else config.users.users.${gate};
  mintSocket = "/run/farm-runner-mint.sock";
  mint = pkgs.writeShellApplication {
    name = "farm-runner-mint";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.curl
      pkgs.jq
    ];
    text = ''
      IFS= read -r -t 10 name || exit 2
      runners=" ${lib.concatStringsSep " " names} "
      case "$runners" in *" $name "*) ;; *) echo "farm-runner-mint: unknown runner $name" >&2; exit 2 ;; esac
      repo=''${name%-*}
      request=$(jq -nc --arg name "${host}-$name-$(date +%s)" --argjson labels '${
        builtins.toJSON (
          [
            "self-hosted"
            "Linux"
            "X64"
          ]
          ++ cfg.labels
        )
      }' '{name: $name, runner_group_id: 1, labels: $labels, work_folder: "_work"}')
      curl -fsS --max-time 20 -K <(printf 'header = "Authorization: Bearer %s"\n' "$(< "$CREDENTIALS_DIRECTORY/token")") \
        -H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28" --data "$request" \
        "https://api.github.com/repos/${cfg.owner}/$repo/actions/runners/generate-jitconfig" | jq -er .encoded_jit_config
    '';
  };
  jitStart =
    name:
    pkgs.writeShellScript "farm-runner-${name}" ''
      ACTIONS_RUNNER_INPUT_JITCONFIG=$(echo ${name} | ${lib.getExe pkgs.socat} -t 30 - UNIX-CONNECT:${mintSocket})
      if [ -z "$ACTIONS_RUNNER_INPUT_JITCONFIG" ]; then
        echo "farm-runner-${name}: no just-in-time registration from ${mintSocket}" >&2
        sleep 60
        exit 1
      fi
      export ACTIONS_RUNNER_INPUT_JITCONFIG
      exec ${podman} run --rm --name farm-${name} ${confine} ${limits} --env ACTIONS_RUNNER_INPUT_JITCONFIG ${image} bash -c 'exec nice -n 19 ./run.sh'
    '';
  egressRules = ''
    for t in iptables ip6tables; do
      $t -D OUTPUT -m owner --uid-owner ${uid} -j farm-egress 2>/dev/null || true
      $t -F farm-egress 2>/dev/null || $t -N farm-egress
      $t -A farm-egress -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
      $t -A farm-egress -o lo -d 127.0.0.53/32 -p udp --dport 53 -j ACCEPT 2>/dev/null || true
      $t -A farm-egress -o lo -d 127.0.0.53/32 -p tcp --dport 53 -j ACCEPT 2>/dev/null || true
      $t -A farm-egress -o lo -d 127.0.0.54/32 -p udp --dport 53 -j ACCEPT 2>/dev/null || true
      $t -A farm-egress -o lo -d 127.0.0.54/32 -p tcp --dport 53 -j ACCEPT 2>/dev/null || true
      $t -A farm-egress -o ${cfg.egressInterface} -p tcp -m multiport --dports ${
        lib.concatMapStringsSep "," toString cfg.egressPorts
      } -m conntrack --ctstate NEW -m limit --limit 200/second --limit-burst 2000 -j ACCEPT
      $t -A farm-egress -j REJECT
      $t -I OUTPUT 1 -m owner --uid-owner ${uid} -j farm-egress
    done
  '';
  gateScript = pkgs.writeShellApplication {
    name = "farm-runner-gate";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.jq
      pkgs.procps
      pkgs.systemd
      pkgs.util-linux
    ];
    text = ''
      state=${gateUser.home}/.local/state/game-reserve/state.json
      gaming=/run/user/$(id -u ${gate})/agent-capacity-v1/gaming.json
      games() {
        local pid
        for pid in $(pgrep -f 'Warcraft III.exe' || true); do
          grep -qE 'libpod|/native.slice/|/agent.slice/' "/proc/$pid/cgroup" 2>/dev/null || return 0
        done
        return 1
      }
      busy() { runuser -u ${user} -- env XDG_RUNTIME_DIR=/run/user/${uid} ${podman} top "farm-$1" -eo args 2>/dev/null | grep -q Runner.Worker; }
      farm() { systemctl --user -M ${user}@ "$@"; }
      if jq -e .on "$state" >/dev/null 2>&1 || jq -e .gaming "$gaming" >/dev/null 2>&1 || games; then
        touch ${pauseMarker}
        for name in ${lib.concatStringsSep " " names}; do
          busy "$name" || farm stop "farm-runner-$name.service" 2>/dev/null || true
        done
      elif [ -e ${pauseMarker} ]; then
        rm -f ${pauseMarker}
        farm start ${lib.concatMapStringsSep " " (n: "farm-runner-${n}.service") names}
      fi
    '';
  };
  buildImage = pkgs.writeShellScript "farm-runner-image" ''
    ${podman} image exists ${image} || ${podman} build -t ${image} -f ${pkgs.writeText "farm-runner.Containerfile" containerfile} ${pkgs.emptyDirectory}
  '';
  register = pkgs.writeShellApplication {
    name = "farm-runner-register";
    excludeShellChecks = [ "SC2016" ];
    runtimeInputs = [
      pkgs.coreutils
      pkgs.systemd
      pkgs.util-linux
    ];
    text = ''
      cd /
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
      as_farm ${podman} run --rm -i ${confine} ${stateMount "\"$dir\""} ${image} bash -c \
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
    }
    // lib.optionalAttrs (!jit || gate != null) {
      ConditionPathExists =
        lib.optional (!jit) "${stateDir}/${name}/.runner" ++ lib.optional (gate != null) "!${pauseMarker}";
    };
    Service = {
      Environment = "PATH=/run/wrappers/bin:/run/current-system/sw/bin";
      ExecStart =
        if jit then
          "${jitStart name}"
        else
          "${podman} run --rm --name farm-${name} ${confine} ${limits} ${stateMount "${stateDir}/${name}"}:ro ${image} bash -c 'cp ${
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
        "gh"
        "libstorm-dev"
        "ripgrep"
        "rsync"
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
    jitTokenFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "/run/secrets/farm-runner-mint-token";
      description = "root-only file holding a fine-grained GitHub token with Administration read and write on the runners' repositories; when set, each container gets a just-in-time registration for one job from a sandboxed mint service, so no runner keeps a reusable credential, and farm-runner-register is not installed";
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
    cpuWeight = lib.mkOption {
      type = lib.types.either (lib.types.ints.between 1 10000) (lib.types.enum [ "idle" ]);
      default = "idle";
      example = 200;
      description = "CPU weight of the runner user's slice: idle keeps jobs behind every interactive app on a desktop, a number above the agent slice's 100 lets landing CI outrank agent builds on a host with no interactive user";
    };
    gameGate.user = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "tom";
      description = "login user whose game signals pause the farm: while their game reserve is on, their capacity gaming hold is set or their Warcraft III client runs outside the agent and native slices, idle runners stop and no runner restarts, and a job already running finishes first; everything resumes when the signals clear, checked every 10 seconds. Null runs the runners at all times";
    };
    cpuQuota = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "1200%";
      description = "CPU quota of the runner user's slice, a ceiling on the cores all runner jobs together may use, leaving the rest of a shared host to its other work; null leaves it unlimited";
    };
  };
  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = nft || config.networking.firewall.enable;
        message = "farm-runners: runner egress is filtered by nftables or the iptables firewall; enable one, or it is unfiltered";
      }
      {
        assertion = gate == null || config.users.users ? ${gate};
        message = "farm-runners: gameGate.user must name a declared user";
      }
      {
        assertion = config.services.resolved.enable;
        message = "farm-runners: runner DNS is allowed only to systemd-resolved on 127.0.0.53/54";
      }
    ];
    virtualisation.podman.enable = true;
    environment.systemPackages = lib.optional (!jit) register;
    systemd = {
      slices."user-${uid}" = {
        overrideStrategy = "asDropin";
        sliceConfig = {
          CPUWeight = cfg.cpuWeight;
          CPUQuota = lib.mkIf (cfg.cpuQuota != null) cfg.cpuQuota;
          IOWeight = 1;
          MemoryMax = cfg.memoryMax;
        };
      };
      sockets.farm-runner-mint = lib.mkIf jit {
        description = "Just-in-time farm runner registrations for the ${user} user";
        wantedBy = [ "sockets.target" ];
        socketConfig = {
          ListenStream = mintSocket;
          SocketUser = "root";
          SocketGroup = user;
          SocketMode = "0660";
          Accept = true;
          MaxConnections = 16;
        };
      };
      services."farm-runner-mint@" = lib.mkIf jit {
        description = "Mint one just-in-time farm runner registration";
        serviceConfig = {
          ExecStart = lib.getExe mint;
          StandardInput = "socket";
          StandardOutput = "socket";
          StandardError = "journal";
          LoadCredential = "token:${cfg.jitTokenFile}";
          DynamicUser = true;
          ProtectSystem = "strict";
          ProtectHome = true;
          PrivateTmp = true;
          PrivateDevices = true;
          ProtectProc = "invisible";
          ProcSubset = "pid";
          ProtectHostname = true;
          ProtectClock = true;
          ProtectKernelTunables = true;
          ProtectKernelModules = true;
          ProtectKernelLogs = true;
          ProtectControlGroups = true;
          NoNewPrivileges = true;
          CapabilityBoundingSet = "";
          RestrictAddressFamilies = [
            "AF_UNIX"
            "AF_INET"
            "AF_INET6"
          ];
          RestrictNamespaces = true;
          RestrictRealtime = true;
          RestrictSUIDSGID = true;
          LockPersonality = true;
          MemoryDenyWriteExecute = true;
          SystemCallArchitectures = "native";
          SystemCallFilter = [
            "@system-service"
            "~@privileged @resources"
          ];
          UMask = "0077";
          RuntimeMaxSec = 60;
        };
      };
    };
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
    networking.firewall = lib.mkIf (!nft) {
      extraCommands = egressRules;
      extraStopCommands = ''
        for t in iptables ip6tables; do
          $t -D OUTPUT -m owner --uid-owner ${uid} -j farm-egress 2>/dev/null || true
          $t -F farm-egress 2>/dev/null || true
          $t -X farm-egress 2>/dev/null || true
        done
      '';
    };
    networking.nftables.tables.farm-egress = lib.mkIf nft {
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
    systemd.services.farm-runner-gate = lib.mkIf (gate != null) {
      description = "Pause the farm runners while ${gate}'s game is running";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = lib.getExe gateScript;
      };
    };
    systemd.timers.farm-runner-gate = lib.mkIf (gate != null) {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "30s";
        OnUnitActiveSec = "10s";
        AccuracySec = "1s";
      };
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
