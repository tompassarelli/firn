{
  pkgs,
  rustPlatform,
  source,
}:

let
  north = rustPlatform.buildRustPackage {
    pname = "north";
    version = "0.1.0";
    src = source;
    cargoLock.lockFile = "${source}/Cargo.lock";
    cargoBuildFlags = [
      "-p"
      "north"
    ];
    doCheck = false;
  };
in
pkgs.runCommand "north-runtime-fixture" { } ''
  install -d $out/tree
  cp ${north}/bin/north $out/north
  ln -s north $out/worker-sandbox
  cp -r ${source}/harness $out/tree/harness
''
