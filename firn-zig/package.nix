{ pkgs, beagle, zig, source }:

pkgs.stdenvNoCC.mkDerivation {
  pname = "firn-native";
  version = "0.1.0";
  src = source;

  nativeBuildInputs = [
    beagle
    pkgs.binutils
    zig
  ];

  dontConfigure = true;

  buildPhase = ''
    runHook preBuild

    export HOME="$TMPDIR/home"
    export ZIG_GLOBAL_CACHE_DIR="$TMPDIR/zig-cache"
    mkdir -p "$HOME" "$ZIG_GLOBAL_CACHE_DIR" build
    beagle build --target zig --exe build/firn-native firn-zig/src/firn/main.bzig

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    install -Dm755 build/firn-native "$out/bin/firn-native"
    strip --strip-debug "$out/bin/firn-native"

    runHook postInstall
  '';

  disallowedReferences = [ zig ];
}
