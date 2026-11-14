{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.myConfig.modules.buildbarn;

  release =
    repo: tag: name: hash:
    let
      src = pkgs.fetchurl {
        url = "https://github.com/buildbarn/${repo}/releases/download/${tag}/${name}.linux_amd64";
        inherit hash;
      };
    in
    "${pkgs.runCommand name { } "install -Dm755 ${src} $out/bin/${name}"}/bin/${name}";
  storageTag = "20261102T091443Z-ca3d8b4";
  executionTag = "20261102T094740Z-c9ba98c";
  bin = {
    storage =
      release "bb-storage" storageTag "bb_storage"
        "sha256-OXDyAWHlaG0VskG6iRUPI7zx16g4LaIBW0vIgjs8F2I=";
    scheduler =
      release "bb-remote-execution" executionTag "bb_scheduler"
        "sha256-aYCiDvKKemuE17tOh1Lo0goSNpjYbDeoHkKKEu3wF/A=";
    worker =
      release "bb-remote-execution" executionTag "bb_worker"
        "sha256-gMIJjoAiCAERd3fnW634vT2RHVpnndbbNIMMjsOG4io=";
    runner =
      release "bb-remote-execution" executionTag "bb_runner"
        "sha256-hGHlHt2W1Gw8rLflzsY93VHHcwJrKfiDNEJZfwQojcU=";
  };

  platformProperties = lib.mapAttrsToList (name: value: { inherit name value; }) cfg.platform;
  messageSize = 16 * 1024 * 1024;
  allow = {
    allow = { };
  };
  identified = cfg.identifiedWorkers;
  workerRole = "worker";
  workersOnly.jmespathExpression.expression = "authenticationMetadata.private.role == '${workerRole}'";
  workerAuthorizer = if identified then workersOnly else allow;
  identityFiles = {
    certificatePath = "${identityDirectory}/cert.pem";
    privateKeyPath = "${identityDirectory}/key.pem";
    refreshInterval = "3600s";
  };
  workerListener =
    port:
    {
      listenAddresses = [ "${cfg.server.address}:${toString port}" ];
    }
    // (
      if identified then
        {
          tls.serverKeyPair.files = identityFiles;
          authenticationPolicy.tlsClientCertificate = {
            clientCertificateAuthorities = lib.concatStrings (lib.attrValues cfg.identities);
            validationJmespathExpression.expression = "`true`";
            metadataExtractionJmespathExpression.expression = "{\"private\": {\"role\": '${workerRole}'}}";
          };
        }
      else
        { authenticationPolicy = allow; }
    );
  asWorker =
    openPort: identifiedPort:
    if identified then
      {
        address = "${cfg.worker.server}:${toString identifiedPort}";
        tls = {
          serverCertificateAuthorities = cfg.identities.${cfg.worker.serverName} or "";
          inherit (cfg.worker) serverName;
          clientKeyPair.files = identityFiles;
        };
      }
    else
      { address = "${cfg.worker.server}:${toString openPort}"; };
  identityUsers = lib.optionals identified (
    lib.optionals cfg.server.enable [
      "buildbarn-frontend.service"
      "buildbarn-scheduler.service"
    ]
    ++ lib.optional cfg.worker.enable "buildbarn-worker.service"
  );
  inner =
    name: port:
    if identified then
      {
        server.listenPaths = [ "/run/buildbarn-${name}.sock" ];
        client.address = "unix:///run/buildbarn-${name}.sock";
      }
    else
      {
        server.listenAddresses = [ "127.0.0.1:${toString port}" ];
        client.address = "127.0.0.1:${toString port}";
      };
  storageEndpoint = inner "storage/storage" storagePort;
  schedulerClientEndpoint = inner "scheduler/client" schedulerClientPort;
  innerDirectory =
    name:
    lib.optionalAttrs identified {
      RuntimeDirectory = "buildbarn-${name}";
      RuntimeDirectoryMode = "0700";
    };
  storageRoot = "/var/lib/buildbarn/storage";
  actionCacheDirectory = "${storageRoot}/ac";
  generationRecord = "/var/lib/buildbarn/action-cache-generation";
  generation = toString cfg.storeGeneration;
  emptyActionCache = pkgs.writeShellScript "buildbarn-action-cache-generation" ''
    set -eu
    recorded=$(cat ${generationRecord} 2>/dev/null || echo none)
    if [ "$recorded" = ${generation} ]; then
      echo "store generation ${generation} is the recorded one: removed nothing under ${actionCacheDirectory}"
      exit 0
    fi
    count=0
    if [ -d ${actionCacheDirectory} ]; then
      count=$(find ${actionCacheDirectory} -xdev -type f | wc -l)
      find ${actionCacheDirectory} -xdev -type f -delete
    fi
    echo ${generation} > ${generationRecord}.new
    mv ${generationRecord}.new ${generationRecord}
    echo "store generation $recorded -> ${generation}: removed $count files under ${actionCacheDirectory}"
  '';
  workerRoot = "/var/lib/buildbarn/worker";
  cacheDirectory = "${workerRoot}/cache";
  buildDirectory = "${workerRoot}/build";
  runnerUser = "buildbarn-run";
  resetBuildDirectory = pkgs.writeShellScript "buildbarn-reset-build-directory" ''
    set -eu
    marker=/var/lib/buildbarn/build-directory-reset
    cd -P -- ${buildDirectory}
    if [ "$(${pkgs.coreutils}/bin/pwd -P)" != ${buildDirectory} ]; then
      echo "refusing to reset ${buildDirectory}: it resolves through a symlink" >&2
      exit 1
    fi
    if [ -e "$marker" ] && [ "$(stat -c '%U:%G %a' .)" = "${runnerUser}:${runnerUser} 2770" ]; then
      exit 0
    fi
    find . -xdev -mindepth 1 -delete
    chown ${runnerUser}:${runnerUser} .
    chmod 2770 .
    touch "$marker"
  '';
  runnerSocket = "/run/buildbarn-runner/runner.sock";
  generationFile = "buildbarn/store-generation";
  slots = lib.genList toString cfg.worker.concurrency;
  slotUser = slot: "buildbarn-run-${slot}";
  slotUnit = slot: "buildbarn-runner-${slot}.service";
  slotRuntime = slot: "buildbarn-runner-${slot}";
  slotSocket = slot: "/run/${slotRuntime slot}/runner.sock";
  slotBuild = slot: "${buildDirectory}/${slot}";
  slotCache = slot: "${cacheDirectory}/${slot}";
  runnerUnits = map slotUnit slots;
  keptSlotBuilds = lib.concatMapStringsSep " -o " (slot: "-path ./${slot}") slots;
  resetSlotDirectories = pkgs.writeShellScript "buildbarn-reset-slot-directories" ''
    set -eu
    marker=/var/lib/buildbarn/build-directory-reset
    layout='${toString cfg.worker.concurrency} slots'
    cd -P -- ${buildDirectory}
    if [ "$(${pkgs.coreutils}/bin/pwd -P)" != ${buildDirectory} ]; then
      echo "refusing to reset ${buildDirectory}: it resolves through a symlink" >&2
      exit 1
    fi
    current() {
      [ "$(cat "$marker" 2>/dev/null)" = "$layout" ] || return 1
      [ "$(stat -c '%U:%G %a' .)" = "buildbarn:buildbarn 711" ] || return 1
      for slot in ${toString slots}; do
        [ "$(stat -c '%U:%G %a' "$slot" 2>/dev/null)" = "${slotUser "$slot"}:${slotUser "$slot"} 2770" ] || return 1
      done
    }
    if current; then
      exit 0
    fi
    find . ${cacheDirectory} -xdev -mindepth 1 ! \( -type d \( ${keptSlotBuilds} \) \) -delete
    chown buildbarn:buildbarn .
    chmod 0711 .
    for slot in ${toString slots}; do
      install -d -m 2770 -o ${slotUser "$slot"} -g ${slotUser "$slot"} "$slot"
      install -d -m 0700 -o buildbarn -g buildbarn ${cacheDirectory}/"$slot"
    done
    echo "$layout" > "$marker"
  '';
  cleanSlot = pkgs.writeShellScript "buildbarn-clean-slot" ''
    set -u
    fail() {
      echo "buildbarn-clean-slot exit $1: $2" | ${pkgs.systemd}/bin/systemd-cat -t buildbarn-clean-slot -p err
      kill -TERM "$PPID"
      exit "$1"
    }
    IFS=: read -r _ _ group < /proc/self/cgroup
    procs=/sys/fs/cgroup$group/cgroup.procs
    round=0
    while :; do
      mapfile -t pids < "$procs" || fail 1 "cannot read $procs"
      others=()
      for pid in "''${pids[@]}"; do
        [ "$pid" = "$$" ] || [ "$pid" = "$PPID" ] || others+=("$pid")
      done
      [ "''${#others[@]}" -gt 0 ] || break
      if [ "$round" -ge 100 ]; then
        fail 2 "processes of the last action outlive the cleaning: ''${others[*]}"
      fi
      kill -STOP "''${others[@]}" 2> /dev/null
      kill -KILL "''${others[@]}" 2> /dev/null
      round=$((round + 1))
      ${pkgs.coreutils}/bin/sleep 0.05
    done
    for directory in /tmp /var/tmp /dev/shm /dev/mqueue; do
      ${pkgs.findutils}/bin/find "$directory" -xdev -mindepth 1 -type d ! -perm -700 -exec ${pkgs.coreutils}/bin/chmod u+rwx {} \;
      ${pkgs.findutils}/bin/find "$directory" -xdev -mindepth 1 -delete
      left=$(${pkgs.coreutils}/bin/ls -A "$directory")
      if [ -n "$left" ]; then
        fail 4 "files of the last action outlive the cleaning in $directory: $left"
      fi
    done
    ${pkgs.util-linux}/bin/ipcrm --all || fail 3 "ipcrm --all failed"
  '';
  closeSocket = pkgs.writeShellScript "buildbarn-close-runner-socket" ''
    set -eu
    directory=/run/$1
    tries=0
    until [ -S "$directory/runner.sock" ]; do
      tries=$((tries + 1))
      [ "$tries" -lt 300 ] || exit 1
      ${pkgs.coreutils}/bin/sleep 0.1
    done
    ${pkgs.coreutils}/bin/chown -h buildbarn:buildbarn "$directory"
    ${pkgs.coreutils}/bin/chmod 0700 "$directory"
    if [ -L "$directory/runner.sock" ] || [ ! -S "$directory/runner.sock" ]; then
      echo "$directory/runner.sock is not a socket the runner made" >&2
      exit 1
    fi
    ${pkgs.coreutils}/bin/chown -h buildbarn:buildbarn "$directory/runner.sock"
    ${pkgs.coreutils}/bin/chmod 0600 "$directory/runner.sock"
  '';
  identityDirectory = "/var/lib/buildbarn/identity";
  inherit (config.networking) hostName;
  makeIdentity = pkgs.writeShellScript "buildbarn-make-identity" ''
    set -eu
    umask 077
    install -d -m 0755 -o root -g root ${identityDirectory}
    cd ${identityDirectory}
    if [ ! -s key.pem ] || [ ! -s cert.pem ]; then
      ${pkgs.openssl}/bin/openssl req -x509 -newkey ed25519 -nodes -days 3650 \
        -subj /CN=${hostName} \
        -addext subjectAltName=DNS:${hostName} \
        -addext extendedKeyUsage=serverAuth,clientAuth \
        -keyout key.pem.new -out cert.pem.new
      mv cert.pem.new cert.pem
      mv key.pem.new key.pem
    fi
    chown root:root cert.pem
    chmod 0444 cert.pem
    chown root:buildbarn key.pem
    chmod 0440 key.pem
  '';
  frontendPort = 8980;
  storagePort = 8981;
  schedulerClientPort = 8982;
  schedulerWorkerPort = 8983;
  workerStorePort = 8984;

  grpc = client: {
    grpc = {
      inherit client;
      enableCompression = true;
    };
  };
  cdcParameterCache = {
    cacheSize = 1000;
    cacheDuration = "60s";
    cacheReplacementPolicy = "LEAST_RECENTLY_USED";
  };
  remoteBlobstore = client: {
    actionCache.completenessChecking = {
      backend = grpc client;
      maximumTotalTreeSizeBytes = 64 * 1024 * 1024;
    };
    contentAddressableStorage = {
      chunkStorage = grpc client;
      chunkMappingStorage.chunkMappingValidating.backend = grpc client;
      inherit cdcParameterCache;
    };
  };

  localStore = name: dataBytes: keyBytes: newBlocks: extra: {
    local = extra // {
      keyLocationMap = {
        onBlockDevice.file = {
          path = "${storageRoot}/${name}/key_location_map";
          sizeBytes = keyBytes;
        };
        maximumGetAttempts = 16;
        maximumPutAttempts = 64;
      };
      oldBlocks = 8;
      currentBlocks = 24;
      inherit newBlocks;
      blocksOnBlockDevice = {
        source.file = {
          path = "${storageRoot}/${name}/blocks";
          sizeBytes = dataBytes;
        };
        spareBlocks = 3;
      };
      persistent = {
        stateDirectoryPath = "${storageRoot}/${name}/persistent_state";
        minimumEpochInterval = "300s";
      };
    };
  };

  gib = n: n * 1024 * 1024 * 1024;
  mib = n: n * 1024 * 1024;

  storageConfig = {
    grpcServers = [
      (storageEndpoint.server // { authenticationPolicy = allow; })
    ];
    maximumMessageSizeBytes = messageSize;
    supportedCompressors = [ "ZSTD" ];
    contentAddressableStorageServer = {
      contentAddressableStorage = {
        chunkStorage = localStore "cas" (gib cfg.server.casSizeGiB) (mib (cfg.server.casSizeGiB * 12)) 3 {
          chunkingParameters = {
            minChunkSizeBytes = 256 * 1024;
            horizonSizeBytes = 8 * 256 * 1024;
          };
        };
        chunkMappingStorage = localStore "cms" (mib 256) (mib 16) 1 { };
      };
      getAuthorizer = allow;
      putAuthorizer = allow;
      findMissingAuthorizer = allow;
      maximumChunkCount = 100000;
    };
    actionCache = {
      backend = localStore "ac" (mib 512) (mib 32) 1 { };
      getAuthorizer = allow;
      putAuthorizer = allow;
    };
  };

  existenceCaching = backend: {
    existenceCaching = {
      inherit backend;
      existenceCache = {
        cacheSize = 1000000;
        cacheDuration = "60s";
        cacheReplacementPolicy = "LEAST_RECENTLY_USED";
      };
    };
  };
  storageAddress = storageEndpoint.client;
  frontendConfig = {
    grpcServers = [
      {
        listenAddresses = [ "${cfg.server.address}:${toString frontendPort}" ];
        authenticationPolicy = allow;
      }
    ]
    ++ lib.optional identified (workerListener workerStorePort);
    schedulers."".endpoint = schedulerClientEndpoint.client // {
      addMetadataJmespathExpression.expression = ''{"build.bazel.remote.execution.v2.requestmetadata-bin": incomingGRPCMetadata."build.bazel.remote.execution.v2.requestmetadata-bin"}'';
    };
    maximumMessageSizeBytes = messageSize;
    supportedCompressors = [ "ZSTD" ];
    contentAddressableStorageServer = {
      contentAddressableStorage = {
        chunkStorage = existenceCaching (grpc storageAddress);
        chunkMappingStorage = existenceCaching {
          chunkMappingValidating.backend = grpc storageAddress;
        };
        inherit cdcParameterCache;
      };
      getAuthorizer = allow;
      putAuthorizer = allow;
      findMissingAuthorizer = allow;
      maximumChunkCount = 100000;
    };
    actionCache = {
      backend.completenessChecking = {
        backend = grpc storageAddress;
        maximumTotalTreeSizeBytes = 64 * 1024 * 1024;
      };
      getAuthorizer = allow;
      putAuthorizer = workerAuthorizer;
    };
    executeAuthorizer = allow;
  };

  schedulerConfig = {
    clientGrpcServers = [ (schedulerClientEndpoint.server // { authenticationPolicy = allow; }) ];
    workerGrpcServers = [ (workerListener schedulerWorkerPort) ];
    contentAddressableStorage = {
      chunkStorage = grpc storageAddress;
      chunkMappingStorage.chunkMappingValidating.backend = grpc storageAddress;
      inherit cdcParameterCache;
    };
    maximumMessageSizeBytes = messageSize;
    executeAuthorizer = allow;
    modifyDrainsAuthorizer = allow;
    killOperationsAuthorizer = allow;
    synchronizeAuthorizer = workerAuthorizer;
    actionRouter.simple = {
      platformKeyExtractor.static.properties = platformProperties;
      invocationKeyExtractors = [
        { correlatedInvocationsId = { }; }
        { toolInvocationId = { }; }
      ];
      initialSizeClassAnalyzer = {
        defaultExecutionTimeout = "1800s";
        maximumExecutionTimeout = "7200s";
      };
    };
    platformQueueWithNoWorkersTimeout = "900s";
  };

  workerConfig = {
    blobstore = remoteBlobstore (asWorker frontendPort workerStorePort);
    maximumMessageSizeBytes = messageSize;
    scheduler = asWorker schedulerWorkerPort schedulerWorkerPort;
    buildDirectories = [
      {
        native = {
          buildDirectoryPath = "${workerRoot}/build";
          cacheDirectoryPath = "${workerRoot}/cache";
          maximumCacheFileCount = 200000;
          maximumCacheSizeBytes = gib cfg.worker.cacheSizeGiB;
          cacheReplacementPolicy = "LEAST_RECENTLY_USED";
        };
        runners = [
          {
            endpoint.address = "unix://${runnerSocket}";
            inherit (cfg.worker) concurrency;
            platform.properties = platformProperties;
            workerId.hostname = hostName;
            environmentVariables.PATH = "/run/current-system/sw/bin";
          }
        ];
      }
    ];
    inputDownloadConcurrency = 32;
    outputUploadConcurrency = 32;
    directoryCache = {
      maximumCount = 10000;
      maximumSizeBytes = 64 * 1024 * 1024;
      cacheReplacementPolicy = "LEAST_RECENTLY_USED";
    };
  };

  runnerConfig = {
    buildDirectoryPath = "${workerRoot}/build";
    grpcServers = [
      {
        listenPaths = [ runnerSocket ];
        authenticationPolicy = allow;
      }
    ];
  };

  slotWorkerConfig = workerConfig // {
    buildDirectories = map (slot: {
      native = {
        buildDirectoryPath = slotBuild slot;
        cacheDirectoryPath = slotCache slot;
        maximumCacheFileCount = 200000 / cfg.worker.concurrency;
        maximumCacheSizeBytes = gib cfg.worker.cacheSizeGiB / cfg.worker.concurrency;
        cacheReplacementPolicy = "LEAST_RECENTLY_USED";
      };
      runners = [
        {
          endpoint.address = "unix://${slotSocket slot}";
          concurrency = 1;
          platform.properties = platformProperties;
          workerId = {
            hostname = hostName;
            inherit slot;
          };
          environmentVariables.PATH = "/run/current-system/sw/bin";
        }
      ];
    }) slots;
  };

  slotRunnerConfig = slot: {
    buildDirectoryPath = slotBuild slot;
    grpcServers = [
      {
        listenPaths = [ (slotSocket slot) ];
        authenticationPolicy = allow;
      }
    ];
    runCommandCleaner = [ "${cleanSlot}" ];
  };

  executorUnits = [
    "buildbarn-worker.service"
  ]
  ++ (if cfg.worker.runnerPerSlot then runnerUnits else [ "buildbarn-runner.service" ]);
  followHold = pkgs.writeShellScript "buildbarn-follow-hold" ''
    set -u
    systemctl=${pkgs.systemd}/bin/systemctl
    ${pkgs.util-linux}/bin/runuser -u ${cfg.worker.hold.user} -- ${cfg.worker.hold.command}
    status=$?
    case $status in
      75)
        if $systemctl is-active --quiet buildbarn-worker.service; then
          echo "the hold check closed this host: stopping ${toString executorUnits}"
          $systemctl --no-block stop ${toString executorUnits}
        fi
        ;;
      0)
        if ! $systemctl is-active --quiet buildbarn-worker.service; then
          echo "the hold check opened this host: starting ${toString executorUnits}"
          $systemctl --no-block start ${toString executorUnits}
        fi
        ;;
      *) echo "the hold check exited $status: the executor stays as it is" ;;
    esac
  '';

  json = name: value: pkgs.writeText "buildbarn-${name}.json" (builtins.toJSON value);

  hardened = {
    User = "buildbarn";
    Group = "buildbarn";
    Restart = "always";
    RestartSec = 5;
    NoNewPrivileges = true;
    ProtectSystem = "strict";
    ProtectHome = true;
    PrivateTmp = true;
    PrivateDevices = true;
    ProtectKernelTunables = true;
    ProtectKernelModules = true;
    ProtectControlGroups = true;
    RestrictSUIDSGID = true;
    LockPersonality = true;
  };
  service = description: binary: configFile: after: extra: {
    inherit description;
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" ] ++ after;
    wants = [ "network-online.target" ];
    serviceConfig = hardened // { ExecStart = "${binary} ${configFile}"; } // extra;
  };
in
{
  options.myConfig.modules.buildbarn = {
    platform = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default.OSFamily = "linux";
      description = "remote execution platform properties every worker advertises; a Buck2 execution platform's remote_execution_properties must equal them for its actions to be scheduled";
    };
    storeGeneration = lib.mkOption {
      type = lib.types.nullOr lib.types.ints.positive;
      default = null;
      description = "number of the action cache's generation. The host with `server.enable` empties the action cache, never the content store, before the store starts whenever this differs from the number recorded in ${generationRecord}, and a host with `client.enable` gets the number and a newline in /etc/${generationFile}, a file only root writes, for a build tool to keep its own state apart per generation. Unset: no unit and no file";
    };
    identifiedWorkers = lib.mkEnableOption "identified workers: the store takes action results and worker registrations only from a holder of a key whose certificate `identities` lists, on listeners of their own, and the store and scheduler talk to each other over sockets only their own user opens";
    identities = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = "host name to the PEM certificate that host's buildbarn-identity unit wrote to ${identityFiles.certificatePath}, read when `identifiedWorkers` is on; a worker requires the store to hold the entry named `worker.serverName`. Public data: each key stays on its host";
    };
    server = {
      enable = lib.mkEnableOption "the Buildbarn content-addressed store, action cache and scheduler that every build host's workers and Buck2 clients share, so an action built once anywhere is fetched, not rebuilt";
      address = lib.mkOption {
        type = lib.types.str;
        description = "private-network address the store and the scheduler's worker endpoint listen on; nothing listens on a public address";
      };
      interface = lib.mkOption {
        type = lib.types.str;
        description = "network interface whose firewall opens the store and worker ports, the private link the address belongs to";
      };
      casSizeGiB = lib.mkOption {
        type = lib.types.ints.positive;
        default = 64;
        description = "size of the content-addressed store's block file; the oldest blocks are dropped when it fills";
      };
    };
    worker = {
      enable = lib.mkEnableOption "a Buildbarn worker that runs remote actions on this host for the scheduler at `worker.server`";
      server = lib.mkOption {
        type = lib.types.str;
        description = "private-network address of the host with `server.enable`";
      };
      serverName = lib.mkOption {
        type = lib.types.str;
        description = "host name of the host with `server.enable`, whose certificate in `identities` this worker requires of the store when `identifiedWorkers` is on";
      };
      concurrency = lib.mkOption {
        type = lib.types.ints.positive;
        description = "actions this worker runs at once";
      };
      cacheSizeGiB = lib.mkOption {
        type = lib.types.ints.positive;
        default = 16;
        description = "size of the worker's local cache of input files, hardlinked into each action's directory";
      };
      allowProcMount = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "lets the runner's actions mount proc inside their own user namespace, by leaving ProtectKernelTunables off the runner unit; a nested sandbox needs that mount";
      };
      runnerUser = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "runs the runner's actions as buildbarn-run, which owns neither the worker's cache nor the inputs it hardlinks, so an action cannot chmod or append a store copy; off keeps the runner as buildbarn";
      };
      runnerPerSlot = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "runs one runner per unit of `concurrency`, each as its own user buildbarn-run-N with its own build directory, input cache, /tmp and shared memory, one action at a time, and ends every process and temporary file of an action before the next starts there, so one action cannot change another's inputs or outputs; off keeps the one runner `runnerUser` describes";
      };
      hold = {
        command = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "command run as `worker.hold.user` every 30 s while the host runs, which takes the worker and its runners out of the grid at run time, with no deploy: exit 75 stops them, exit 0 starts them, and any other exit leaves them as they are; nothing else starts them, neither boot nor a deploy. Null: no check, the worker runs whenever the host does";
        };
        user = lib.mkOption {
          type = lib.types.str;
          default = "root";
          description = "user `worker.hold.command` runs as";
        };
      };
    };
    client = {
      enable = lib.mkEnableOption "/etc/buckconfig.d/remote-execution, which points every Buck2 project on this host at the Buildbarn store and scheduler at `client.server`";
      server = lib.mkOption {
        type = lib.types.str;
        description = "private-network address of the host with `server.enable`";
      };
    };
  };

  config = lib.mkMerge [
    (lib.mkIf (cfg.server.enable || cfg.worker.enable) {
      users.users.buildbarn = {
        isSystemUser = true;
        group = "buildbarn";
      };
      users.groups.buildbarn = { };
      assertions = lib.optionals (identified && cfg.worker.enable) [
        {
          assertion = cfg.worker.runnerUser || cfg.worker.runnerPerSlot;
          message = "myConfig.modules.buildbarn.identifiedWorkers needs worker.runnerUser, so that an action does not run as the user that reads the worker's key";
        }
        {
          assertion = cfg.identities ? ${cfg.worker.serverName};
          message = "myConfig.modules.buildbarn.identities has no certificate for the store host ${cfg.worker.serverName}";
        }
      ];
      systemd.tmpfiles.rules = [ "d /var/lib/buildbarn 0755 root root -" ];
      systemd.services.buildbarn-identity = {
        description = "Make this host's Buildbarn key and certificate once, the key readable by root and the buildbarn user only";
        wantedBy = [ "multi-user.target" ];
        before = identityUsers;
        requiredBy = identityUsers;
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = makeIdentity;
        };
      };
    })
    (lib.mkIf cfg.server.enable {
      systemd.services = {
        buildbarn-storage =
          service "Buildbarn content-addressed store and action cache, loopback only" bin.storage
            (json "storage" storageConfig)
            [ ]
            (
              innerDirectory "storage"
              // {
                StateDirectory = map (d: "buildbarn/storage/${d}") [
                  "cas"
                  "cas/persistent_state"
                  "cms"
                  "cms/persistent_state"
                  "ac"
                  "ac/persistent_state"
                ];
              }
            );
        buildbarn-scheduler =
          service "Buildbarn scheduler: queues remote actions for the build hosts' workers" bin.scheduler
            (json "scheduler" schedulerConfig)
            [ "buildbarn-storage.service" ]
            (innerDirectory "scheduler");
        buildbarn-frontend =
          service
            "Buildbarn frontend: the store, action cache and execution endpoint Buck2 clients and workers reach over the private network"
            bin.storage
            (json "frontend" frontendConfig)
            [ "buildbarn-storage.service" "buildbarn-scheduler.service" ]
            { };
      };
      networking.firewall.interfaces.${cfg.server.interface}.allowedTCPPorts = [
        frontendPort
        schedulerWorkerPort
      ]
      ++ lib.optional identified workerStorePort;
    })
    (lib.mkIf (cfg.server.enable && cfg.storeGeneration != null) {
      systemd.services = {
        buildbarn-action-cache-generation = {
          description = "Empty the Buildbarn action cache once per store generation, before the store starts";
          before = [ "buildbarn-storage.service" ];
          requiredBy = [ "buildbarn-storage.service" ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStart = emptyActionCache;
          };
        };
        buildbarn-storage.restartTriggers = [ generation ];
      };
    })
    (lib.mkIf (cfg.client.enable && cfg.storeGeneration != null) {
      environment.etc.${generationFile} = {
        mode = "0444";
        text = "${generation}\n";
      };
    })
    (lib.mkIf (cfg.worker.enable && cfg.worker.runnerUser && !cfg.worker.runnerPerSlot) {
      users.users.${runnerUser} = {
        isSystemUser = true;
        group = runnerUser;
      };
      users.groups.${runnerUser} = { };
      systemd.tmpfiles.rules = [
        "d ${workerRoot} 0751 buildbarn buildbarn -"
        "d ${cacheDirectory} 0700 buildbarn buildbarn -"
        "d ${buildDirectory} 2770 ${runnerUser} ${runnerUser} -"
      ];
      systemd.services.buildbarn-build-directory-reset = {
        description = "Empty the Buildbarn build directory once and give it to the runner user, before the runner and the worker start";
        before = [
          "buildbarn-runner.service"
          "buildbarn-worker.service"
        ];
        requiredBy = [
          "buildbarn-runner.service"
          "buildbarn-worker.service"
        ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = resetBuildDirectory;
        };
      };
    })
    (lib.mkIf (cfg.worker.enable && !cfg.worker.runnerPerSlot) {
      systemd.services = {
        buildbarn-runner =
          service
            "Buildbarn runner: executes remote actions with no network, no home directories and a private /tmp"
            bin.runner
            (json "runner" runnerConfig)
            [ ]
            (
              {
                RuntimeDirectory = "buildbarn-runner";
                RuntimeDirectoryMode = "0750";
                PrivateNetwork = true;
                ProtectKernelTunables = !cfg.worker.allowProcMount;
                Nice = 10;
                CPUWeight = 50;
                IOWeight = 50;
              }
              // (
                if cfg.worker.runnerUser then
                  {
                    User = runnerUser;
                    Group = runnerUser;
                    UMask = "0007";
                    ReadWritePaths = [ buildDirectory ];
                  }
                else
                  {
                    StateDirectory = [
                      "buildbarn/worker"
                      "buildbarn/worker/build"
                    ];
                  }
              )
            );
        buildbarn-worker =
          service
            "Buildbarn worker: fetches action inputs from the shared store, hands each action to the runner and uploads its outputs"
            bin.worker
            (json "worker" workerConfig)
            [ "buildbarn-runner.service" ]
            (
              if cfg.worker.runnerUser then
                {
                  SupplementaryGroups = [ runnerUser ];
                  UMask = "0002";
                  ReadWritePaths = [ workerRoot ];
                }
              else
                {
                  StateDirectory = [
                    "buildbarn/worker"
                    "buildbarn/worker/build"
                    "buildbarn/worker/cache"
                  ];
                }
            )
          // {
            bindsTo = [ "buildbarn-runner.service" ];
          };
      };
    })
    (lib.mkIf cfg.worker.enable {
      assertions = [
        {
          assertion = (config.boot.kernel.sysctl."kernel.yama.ptrace_scope" or 1) >= 1;
          message = "myConfig.modules.buildbarn.worker needs kernel.yama.ptrace_scope at 1 or above, the kernel's default: a remote action must not trace the runner that started it";
        }
      ];
    })
    (lib.mkIf (cfg.worker.enable && cfg.worker.runnerPerSlot) {
      boot.kernel.sysctl."kernel.yama.ptrace_scope" = lib.mkDefault 1;
      users.users = lib.genAttrs (map slotUser slots) (user: {
        isSystemUser = true;
        group = user;
      });
      users.groups = lib.genAttrs (map slotUser slots) (_: { });
      systemd.tmpfiles.rules = [
        "d ${workerRoot} 0751 buildbarn buildbarn -"
        "d ${cacheDirectory} 0700 buildbarn buildbarn -"
        "d ${buildDirectory} 0711 buildbarn buildbarn -"
      ]
      ++ lib.concatMap (slot: [
        "d ${slotCache slot} 0700 buildbarn buildbarn -"
        "d ${slotBuild slot} 2770 ${slotUser slot} ${slotUser slot} -"
      ]) slots;
      systemd.services = {
        buildbarn-build-directory-reset = {
          description = "Empty the Buildbarn build and cache directories when their layout changes and give each slot's build directory to its runner user, before the runners and the worker start";
          before = runnerUnits ++ [ "buildbarn-worker.service" ];
          requiredBy = runnerUnits ++ [ "buildbarn-worker.service" ];
          serviceConfig = {
            Type = "oneshot";
            ExecStart = resetSlotDirectories;
          };
        };
        buildbarn-worker =
          service
            "Buildbarn worker: fetches action inputs from the shared store, hands each action to its slot's runner and uploads its outputs"
            bin.worker
            (json "worker" slotWorkerConfig)
            runnerUnits
            {
              SupplementaryGroups = map slotUser slots;
              UMask = "0002";
              ReadWritePaths = [ workerRoot ];
            }
          // {
            bindsTo = runnerUnits;
            upheldBy = runnerUnits;
          };
      }
      // lib.listToAttrs (
        map (
          slot:
          lib.nameValuePair (lib.removeSuffix ".service" (slotUnit slot)) (
            service
              "Buildbarn runner of slot ${slot}: executes one remote action at a time as its own user, with no network, no home directories and a /tmp, shared memory and process table emptied between actions"
              bin.runner
              (json "runner-${slot}" (slotRunnerConfig slot))
              [ ]
              {
                User = slotUser slot;
                Group = slotUser slot;
                UMask = "0007";
                ReadWritePaths = [ (slotBuild slot) ];
                RuntimeDirectory = slotRuntime slot;
                RuntimeDirectoryMode = "0750";
                ExecStartPost = "+${closeSocket} ${slotRuntime slot}";
                PrivateNetwork = true;
                PrivateIPC = true;
                TemporaryFileSystem = "/dev/shm:mode=1777";
                ProtectKernelTunables = !cfg.worker.allowProcMount;
                Nice = 10;
                CPUWeight = 50;
                IOWeight = 50;
              }
          )
        ) slots
      );
    })
    (lib.mkIf (cfg.worker.enable && cfg.worker.hold.command != null) {
      systemd.services =
        lib.genAttrs (map (lib.removeSuffix ".service") executorUnits) (_: {
          wantedBy = lib.mkForce [ ];
        })
        // {
          buildbarn-hold = {
            description = "Start the Buildbarn worker and its runners while the hold check opens this host, and stop them while it closes it; nothing else starts them, so neither a deploy nor a boot runs the executor on a held host";
            serviceConfig = {
              Type = "oneshot";
              ExecStart = followHold;
              TimeoutStartSec = 25;
            };
          };
        };
      systemd.timers.buildbarn-hold = {
        description = "Run the Buildbarn hold check every 30 s";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnBootSec = 30;
          OnUnitActiveSec = 30;
          AccuracySec = 1;
        };
      };
    })
    (lib.mkIf cfg.client.enable {
      environment.etc."buckconfig.d/remote-execution" = {
        mode = "0444";
        text = ''
          [buck2_re_client]
          engine_address = grpc://${cfg.client.server}:${toString frontendPort}
          action_cache_address = grpc://${cfg.client.server}:${toString frontendPort}
          cas_address = grpc://${cfg.client.server}:${toString frontendPort}
          tls = false
        '';
      };
    })
  ];
}
