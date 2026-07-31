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
  in
    assert !(builtins.hasAttr \"north-reactor\" home.systemd.user.services);
    assert builtins.hasAttr \"north-rebuild-queue-owner\" home.systemd.user.services;
    assert builtins.hasAttr \"north-reactor-sweep\" home.systemd.user.services;
    assert builtins.hasAttr \"north-reactor-sweep\" home.systemd.user.timers;
    assert owner.Service.Type == \"simple\";
    assert owner.Service.Restart == \"always\";
    assert owner.Service.RestartSec == \"1s\";
    assert owner.Install.WantedBy == [ \"default.target\" ];
    assert builtins.match \".*cli/rebuild-window-watch.clj\" owner.Service.ExecStart != null;
    assert sweep.Unit.X-SwitchMethod == \"keep-old\";
    assert !(sweep.Service ? restartIfChanged);
    assert builtins.head owner.Service.Environment == \"PATH=/systemd/bin:/bb/bin:/coreutils/bin:/git/bin\";
    assert builtins.head sweep.Service.Environment == \"PATH=/systemd/bin:/bb/bin:/coreutils/bin:/git/bin\";
    \"ok\"
" | grep -Fxq ok

printf 'ok: event-driven rebuild owner and periodic reactor fallback are wired\n'
