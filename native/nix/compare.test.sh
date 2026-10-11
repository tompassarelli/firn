#!/usr/bin/env bash
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/../.." && pwd)"
workbench="${1:-${FIRN_CLAUSE_WORKBENCH:-${FIRN_RUNTIME_ROOT:-$HOME/.local/lib/firn/cli}/current/bin/clause-workbench}}"
discovered="${2:-$repo}"
output="$repo/.firn-build/nix-comparison"
mkdir -p "$output/baseline"

for name in btop jq gnome-keyring kitty ladybird; do
  git -C "$repo" show "d5734ff6:modules/$name/default.nix" >"$output/baseline/$name.nix"
  "$workbench" check-source "$here/$name.clause"
  "$workbench" compile-nix "$here/$name.clause" "$name-module" "$output/$name.nix"
done

# Nix's module evaluator is the foreign-system boundary being compared.
FIRN_NIX_COMPARISON_REPO="$repo" FIRN_NIX_COMPARISON_OUTPUT="$output" \
FIRN_NIX_COMPARISON_DISCOVERED="$discovered" \
  nix eval --impure --json --expr '
    let
      repo = builtins.getEnv "FIRN_NIX_COMPARISON_REPO";
      output = builtins.getEnv "FIRN_NIX_COMPARISON_OUTPUT";
      discovered = builtins.getEnv "FIRN_NIX_COMPARISON_DISCOVERED";
      flake = builtins.getFlake ("git+file://" + repo);
      pkgs = (import flake.inputs.nixpkgs { system = "x86_64-linux"; }) // {
        unstable = import flake.inputs.nixpkgs-unstable { system = "x86_64-linux"; };
      };
      lib = pkgs.lib;
      inspect = name: module: username: enabled:
        let
          evaluated = lib.evalModules {
            specialArgs = { inherit pkgs; };
            modules = [
              { options.myConfig.modules.users.username = lib.mkOption {
                  type = lib.types.str;
                  default = username;
                };
                options.home-manager.users = lib.mkOption {
                  type = lib.types.attrsOf lib.types.anything;
                  default = {};
                };
                options.environment.systemPackages = lib.mkOption {
                  type = lib.types.listOf lib.types.package;
                  default = [];
                };
                options.security.pam.services.login.enableGnomeKeyring = lib.mkEnableOption "GNOME Keyring login";
                options.services.gnome.gnome-keyring.enable = lib.mkEnableOption "GNOME Keyring service";
                options.programs.seahorse.enable = lib.mkEnableOption "Seahorse";
              }
              module
            ] ++ lib.optional (enabled != null) {
              myConfig.modules.${name}.enable = enabled;
            };
          };
          option = evaluated.options.myConfig.modules.${name}.enable;
        in {
          enabled = evaluated.config.myConfig.modules.${name}.enable;
          packages = map (package: {
            inherit (package) name outPath;
          }) evaluated.config.environment.systemPackages;
          type = option.type.name;
          default = option.default;
          home = evaluated.config.home-manager.users;
          settings = with evaluated.config; {
            login = security.pam.services.login.enableGnomeKeyring;
            service = services.gnome.gnome-keyring.enable;
            seahorse = programs.seahorse.enable;
          };
        };
      compare = name: map (username: map (enabled:
        let
          actual = inspect name (import (output + "/" + name + ".nix")) username enabled;
          selected = inspect name (import (discovered + "/modules/" + name + "/default.nix")) username enabled;
          expected = inspect name (import (output + "/baseline/" + name + ".nix")) username enabled;
        in assert actual == expected; assert selected == expected; actual
      ) [ null false true ]) [ "tom" "tom-test.user" ];
    in { btop = compare "btop"; jq = compare "jq"; gnome-keyring = compare "gnome-keyring"; kitty = compare "kitty"; ladybird = compare "ladybird"; }
  '
