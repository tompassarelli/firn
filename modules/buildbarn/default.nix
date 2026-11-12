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
  storageRoot = "/var/lib/buildbarn/storage";
  workerRoot = "/var/lib/buildbarn/worker";
  cacheDirectory = "${workerRoot}/cache";
  buildDirectory = "${workerRoot}/build";
  runnerUser = "buildbarn-run";
  resetBuildDirectory = pkgs.writeShellScript "buildbarn-reset-build-directory" ''
    set -eu
    marker=/var/lib/buildbarn/build-directory-reset
    if [ ! -e "$marker" ]; then
      if [ -L ${buildDirectory} ]; then
        echo "refusing to reset ${buildDirectory}: it is a symlink" >&2
        exit 1
      fi
      rm -rf -- ${buildDirectory}
      mkdir -m 2770 -- ${buildDirectory}
      chown ${runnerUser}:${runnerUser} ${buildDirectory}
      chmod 2770 ${buildDirectory}
      touch "$marker"
    fi
  '';
  runnerSocket = "/run/buildbarn-runner/runner.sock";
  frontendPort = 8980;
  storagePort = 8981;
  schedulerClientPort = 8982;
  schedulerWorkerPort = 8983;

  grpc = address: {
    grpc = {
      client.address = address;
      enableCompression = true;
    };
  };
  cdcParameterCache = {
    cacheSize = 1000;
    cacheDuration = "60s";
    cacheReplacementPolicy = "LEAST_RECENTLY_USED";
  };
  remoteBlobstore = address: {
    actionCache.completenessChecking = {
      backend = grpc address;
      maximumTotalTreeSizeBytes = 64 * 1024 * 1024;
    };
    contentAddressableStorage = {
      chunkStorage = grpc address;
      chunkMappingStorage.chunkMappingValidating.backend = grpc address;
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
      {
        listenAddresses = [ "127.0.0.1:${toString storagePort}" ];
        authenticationPolicy = allow;
      }
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
  storageAddress = "127.0.0.1:${toString storagePort}";
  frontendConfig = {
    grpcServers = [
      {
        listenAddresses = [ "${cfg.server.address}:${toString frontendPort}" ];
        authenticationPolicy = allow;
      }
    ];
    schedulers."".endpoint = {
      address = "127.0.0.1:${toString schedulerClientPort}";
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
      putAuthorizer = allow;
    };
    executeAuthorizer = allow;
  };

  schedulerConfig = {
    clientGrpcServers = [
      {
        listenAddresses = [ "127.0.0.1:${toString schedulerClientPort}" ];
        authenticationPolicy = allow;
      }
    ];
    workerGrpcServers = [
      {
        listenAddresses = [ "${cfg.server.address}:${toString schedulerWorkerPort}" ];
        authenticationPolicy = allow;
      }
    ];
    contentAddressableStorage = {
      chunkStorage = grpc storageAddress;
      chunkMappingStorage.chunkMappingValidating.backend = grpc storageAddress;
      inherit cdcParameterCache;
    };
    maximumMessageSizeBytes = messageSize;
    executeAuthorizer = allow;
    modifyDrainsAuthorizer = allow;
    killOperationsAuthorizer = allow;
    synchronizeAuthorizer = allow;
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
    blobstore = remoteBlobstore "${cfg.worker.server}:${toString frontendPort}";
    maximumMessageSizeBytes = messageSize;
    scheduler.address = "${cfg.worker.server}:${toString schedulerWorkerPort}";
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
            workerId.hostname = config.networking.hostName;
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
    })
    (lib.mkIf cfg.server.enable {
      systemd.services = {
        buildbarn-storage =
          service "Buildbarn content-addressed store and action cache, loopback only" bin.storage
            (json "storage" storageConfig)
            [ ]
            {
              StateDirectory = map (d: "buildbarn/storage/${d}") [
                "cas"
                "cas/persistent_state"
                "cms"
                "cms/persistent_state"
                "ac"
                "ac/persistent_state"
              ];
            };
        buildbarn-scheduler =
          service "Buildbarn scheduler: queues remote actions for the build hosts' workers" bin.scheduler
            (json "scheduler" schedulerConfig)
            [ "buildbarn-storage.service" ]
            { };
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
      ];
    })
    (lib.mkIf (cfg.worker.enable && cfg.worker.runnerUser) {
      users.users.${runnerUser} = {
        isSystemUser = true;
        group = runnerUser;
      };
      users.groups.${runnerUser} = { };
      systemd.tmpfiles.rules = [
        "d /var/lib/buildbarn 0755 root root -"
        "d ${workerRoot} 0751 buildbarn buildbarn -"
        "d ${cacheDirectory} 0700 buildbarn buildbarn -"
        "d ${buildDirectory} 2770 ${runnerUser} ${runnerUser} -"
      ];
    })
    (lib.mkIf cfg.worker.enable {
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
                    ExecStartPre = "+${resetBuildDirectory}";
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
