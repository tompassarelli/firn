#!/usr/bin/env bash
set -euo pipefail

repo=$(cd "$(dirname "$0")/../.." && pwd)
generated_module=$repo/modules/north-reactor/default.nix

nix eval --raw --impure --expr "
  let
    module = import $generated_module {
      config = {
        myConfig.modules.users.username = \"tom\";
        myConfig.modules.north-reactor.enable = true;
        myConfig.modules.north-reactor.eventOwner.enable = true;
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
    owner = home.systemd.user.services.north-rebuild-queue-owner;
    sweep = home.systemd.user.services.north-reactor-sweep;
    ownerServices = builtins.filter
      (name:
        let
          service = builtins.getAttr name home.systemd.user.services;
          exec = if service ? Service && service.Service ? ExecStart
            then service.Service.ExecStart
            else \"\";
        in builtins.match \".*cli/rebuild-window-watch[.]clj\" exec != null)
      (builtins.attrNames home.systemd.user.services);
  in
    assert !(builtins.hasAttr \"north-reactor\" home.systemd.user.services);
    assert builtins.hasAttr \"north-rebuild-queue-owner\" home.systemd.user.services;
    assert ownerServices == [ \"north-rebuild-queue-owner\" ];
    assert !(builtins.hasAttr \"north-rebuild-queue-owner\" home.systemd.user.timers);
    assert builtins.hasAttr \"north-reactor-sweep\" home.systemd.user.services;
    assert builtins.hasAttr \"north-reactor-sweep\" home.systemd.user.timers;
    assert owner.Service.Type == \"simple\";
    assert owner.Service.Restart == \"always\";
    assert owner.Service.RestartSec == \"1s\";
    assert owner.Install.WantedBy == [ \"default.target\" ];
    assert owner.Unit.ConditionPathExists == \"%h/.local/state/north/runtime/current/cli/rebuild-window-watch.clj\";
    assert owner.Service.WorkingDirectory == \"%h/.local/state/north/runtime/current\";
    assert owner.Service.ExecStart == \"/bb/bin/bb %h/.local/state/north/runtime/current/cli/rebuild-window-watch.clj\";
    assert builtins.match \".*north-runtime-exec.*\" owner.Service.ExecStart == null;
    assert !(owner.Service ? ExecStartPre);
    assert !(owner.Service ? ExecStartPost);
    assert sweep.Unit.X-SwitchMethod == \"keep-old\";
    assert !(sweep.Service ? restartIfChanged);
    assert sweep.Service.Type == \"oneshot\";
    assert sweep.Service.ExecStart == \"/runtime/bin/north-runtime-exec --chdir --interp /bb/bin/bb /north cli/north-reactor.clj sweep-once\";
    assert home.systemd.user.timers.north-reactor-sweep.Timer.OnUnitInactiveSec == \"5m\";
    assert home.systemd.user.timers.north-reactor-sweep.Timer.Persistent;
    assert builtins.head owner.Service.Environment == \"PATH=/systemd/bin:/bb/bin:/coreutils/bin:/git/bin\";
    assert builtins.head sweep.Service.Environment == \"PATH=/systemd/bin:/bb/bin:/coreutils/bin:/git/bin\";
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
    assert host.myConfig.modules.north-reactor.enable;
    assert host.myConfig.modules.north-reactor.eventOwner.enable;
    \"ok\"
" | grep -Fxq ok

nix eval --raw --impure --expr "
  let
    config = (builtins.getFlake (toString $repo)).nixosConfigurations.whiterabbit.config;
    services = config.home-manager.users.tom.systemd.user.services;
    timers = config.home-manager.users.tom.systemd.user.timers;
    owner = services.north-rebuild-queue-owner;
    ownerServices = builtins.filter
      (name:
        let
          service = builtins.getAttr name services;
          execStarts = (service.Service or {}).ExecStart or [];
        in builtins.any
          (exec: builtins.match \".*cli/rebuild-window-watch[.]clj\" exec != null)
          execStarts)
      (builtins.attrNames services);
  in
    assert config.myConfig.modules.north-reactor.eventOwner.enable;
    assert ownerServices == [ \"north-rebuild-queue-owner\" ];
    assert !(builtins.hasAttr \"north-rebuild-queue-owner\" config.systemd.services);
    assert !(builtins.hasAttr \"north-rebuild-queue-owner\" timers);
    assert builtins.length owner.Service.ExecStart == 1;
    assert builtins.match
      \".*/bb %h/.local/state/north/runtime/current/cli/rebuild-window-watch[.]clj\"
      (builtins.head owner.Service.ExecStart) != null;
    assert owner.Unit.ConditionPathExists == \"%h/.local/state/north/runtime/current/cli/rebuild-window-watch.clj\";
    assert owner.Service.WorkingDirectory == \"%h/.local/state/north/runtime/current\";
    assert !(owner.Service ? ExecStartPre);
    assert !(owner.Service ? ExecStartPost);
    assert timers.north-reactor-sweep.Timer.OnUnitInactiveSec == \"5m\";
    assert timers.north-reactor-sweep.Timer.Persistent;
    \"ok\"
" | grep -Fxq ok

printf 'ok: one event owner, no inline retry, and periodic fallback are wired\n'
