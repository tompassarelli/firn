#!/usr/bin/env bash
set -euo pipefail

repo=$(cd "$(dirname "$0")/../.." && pwd)
generated_module=$repo/modules/north-coordination-workers/default.nix

nix eval --raw --impure --expr "
  let
    module = import $generated_module {
      config = {
        myConfig.modules.users.username = \"tom\";
        myConfig.modules.north-coordination-workers.enable = true;
      };
      lib = {
        mkEnableOption = _: {};
        mkIf = condition: value: if condition then value else {};
      };
      pkgs = {
        stdenv.hostPlatform.system = \"test\";
        systemd = \"/systemd\";
        babashka = \"/bb\";
        coreutils = \"/coreutils\";
        git = \"/git\";
        writeShellApplication = _: \"/runtime\";
      };
      inputs.north.packages.test.default = \"/north\";
    };
    home = module.config.home-manager.users.tom { config = {}; };
    services = home.systemd.user.services;
    timers = home.systemd.user.timers;
    rebuild = services.north-nix-rebuild-worker;
    concerns = services.north-concern-reconciliation-worker;
    attention = services.north-attention-reconciliation-worker;
    projection = services.north-coordination-projection-worker;
  in
    assert rebuild.Service.Type == \"simple\";
    assert rebuild.Unit.X-SwitchMethod == \"keep-old\";
    assert concerns.Service.Type == \"simple\";
    assert attention.Service.Type == \"simple\";
    assert projection.Service.Type == \"simple\";
    assert rebuild.Service.ExecStart ==
      \"/bb/bin/bb %h/.local/state/north/runtime/current/cli/nix-rebuild-worker.clj\";
    assert rebuild.Service.Environment == [
      \"PATH=/systemd/bin:/bb/bin:/coreutils/bin:/git/bin:/run/current-system/sw/bin\"
      \"FIRN_BIN=%h/.local/bin/firn\"
    ];
    assert concerns.Service.ExecStart ==
      \"/bb/bin/bb %h/.local/state/north/runtime/current/cli/reconciliation-worker-host.clj concerns\";
    assert attention.Service.ExecStart ==
      \"/bb/bin/bb %h/.local/state/north/runtime/current/cli/reconciliation-worker-host.clj attention\";
    assert projection.Service.ExecStart ==
      \"/bb/bin/bb %h/.local/state/north/runtime/current/cli/coordination-projection-worker-host.clj\";
    assert timers.north-spend-guard-worker.Timer.OnUnitInactiveSec == \"1m\";
    assert timers.north-lane-lifecycle-janitor.Timer.OnUnitInactiveSec == \"5m\";
    assert timers.north-stale-concern-janitor.Timer.OnUnitInactiveSec == \"15m\";
    assert timers.north-worktree-janitor.Timer.OnUnitInactiveSec == \"15m\";
    assert timers.north-agent-log-janitor.Timer.OnUnitInactiveSec == \"1h\";
    assert home.systemd.user.paths.north-runtime-worker-restart.Path.PathChanged ==
      \"%h/.local/state/north/runtime/current\";
    \"ok\"
" | grep -Fxq ok

nix eval --raw --impure --expr "
  let
    host = import $repo/hosts/whiterabbit/configuration.nix {
      config.sops.secrets.\"wireguard-laptop\".path = \"/wireguard-key\";
      lib.mkForce = value: value;
      pkgs = {};
    };
  in
    assert host.myConfig.modules.north-coordination-workers.enable;
    \"ok\"
" | grep -Fxq ok

printf 'ok: North coordination responsibilities are independently supervised\n'
