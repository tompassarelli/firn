{ config, lib, pkgs, ... }:

let
  firnProfile = pkgs.rustPlatform.buildRustPackage {
    pname = "firn-profile";
    version = "0.1.0";
    src = lib.fileset.toSource {
      root = ../tools/firn;
      fileset = lib.fileset.unions [
        ../tools/firn/Cargo.toml
        ../tools/firn/Cargo.lock
        ../tools/firn/src/profile.rs
        ../tools/firn/src/bin/firn-profile.rs
      ];
    };
    cargoLock.lockFile = ../tools/firn/Cargo.lock;
    cargoBuildFlags = [ "--bin" "firn-profile" ];
    doCheck = false;
  };
in
{
  home.packages = [ firnProfile ];
  home.activation.installPackages = lib.mkForce (
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      if [[ -e ${config.home.profileDirectory}/manifest.json ]]; then
        run ${firnProfile}/bin/firn-profile replace home-manager-path ${config.home.path}
      else
        run nix-env -i ${config.home.path}
      fi
    ''
  );
}
