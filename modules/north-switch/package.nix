{ rustPlatform, source }:
rustPlatform.buildRustPackage {
  pname = "north-switch";
  version = "git";
  src = source;
  cargoLock.lockFile = "${source}/Cargo.lock";
  postPatch = ''
    rm -f .cargo/config.toml rust-toolchain.toml
  '';
  cargoBuildFlags = [
    "-p"
    "north-switch"
  ];
  doCheck = false;
  postInstall = ''
    ln -s north-switch $out/bin/north
  '';
}
