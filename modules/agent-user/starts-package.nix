{ rustPlatform, source }:
rustPlatform.buildRustPackage {
  pname = "north-agent-starts";
  version = "git";
  src = source;
  cargoLock.lockFile = "${source}/Cargo.lock";
  postPatch = ''
    rm -f .cargo/config.toml rust-toolchain.toml
  '';
  cargoBuildFlags = [
    "-p"
    "north-agent-starts"
  ];
  doCheck = false;
}
