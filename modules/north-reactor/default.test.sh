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
        babashka = \"/bb\";
        coreutils = \"/coreutils\";
        git = \"/git\";
      };
      inputs.north.packages.test.default = \"/north\";
    };
    home = module.config.home-manager.users.tom { config = {}; };
    sweep = home.systemd.user.services.north-reactor-sweep;
  in
    assert sweep.restartIfChanged == false;
    assert !(sweep.Service ? restartIfChanged);
    assert builtins.head sweep.Service.Environment == \"PATH=/bb/bin:/coreutils/bin:/git/bin\";
    \"ok\"
" | grep -Fxq ok

printf 'ok: north-reactor-sweep does not restart on Home Manager unit changes and resolves git at runtime\n'
