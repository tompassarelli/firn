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
      };
      inputs.north.packages.test.default = \"/north\";
    };
    home = module.config.home-manager.users.tom { config = {}; };
    sweep = home.systemd.user.services.north-reactor-sweep;
  in
    assert !(builtins.hasAttr \"north-reactor\" home.systemd.user.services);
    assert builtins.hasAttr \"north-reactor-sweep\" home.systemd.user.services;
    assert builtins.hasAttr \"north-reactor-sweep\" home.systemd.user.timers;
    assert sweep.Unit.X-SwitchMethod == \"keep-old\";
    assert !(sweep.Service ? restartIfChanged);
    assert builtins.head sweep.Service.Environment == \"PATH=/systemd/bin:/bb/bin:/coreutils/bin:/git/bin\";
    \"ok\"
" | grep -Fxq ok

printf 'ok: only north-reactor-sweep remains, with its timer and runtime dependencies\n'
