{ config, lib, pkgs, inputs, ... }:

let
  username = config.myConfig.modules.users.username;
  homeDir = config.myConfig.modules.users.homeDir;
  framPkg = inputs.fram.packages."${pkgs.stdenv.hostPlatform.system}".default;
  framRev = inputs.fram.rev;
  northPkg = inputs.north.packages."${pkgs.stdenv.hostPlatform.system}".default;
  runtimeState = "${homeDir}/.local/state/north/fram-runtime";
  northCoordRuntime = pkgs.writeShellApplication {
    name = "north-coord-runtime";
    runtimeInputs = with pkgs; [ bash coreutils git iproute2 systemd util-linux ];
    text = ''
      export NORTH_COORD_RUNTIME_STATE=${runtimeState}
      export NORTH_COORD_FRAM_PACKAGE=${framPkg}
      export NORTH_COORD_FRAM_PACKAGE_REV=${framRev}
      export NORTH_COORD_FRAM_CHECKOUT=${homeDir}/code/fram
      export NORTH_COORD_NORTH_PACKAGE=${northPkg}
      export NORTH_COORD_FRAM_LOG=${homeDir}/.local/state/north/coordination.log
      export NORTH_COORD_TELEMETRY_LOG=${homeDir}/.local/state/north/telemetry.log
      export NORTH_COORD_SYSTEMD_UNIT=north-coord.service
      export NORTH_COORD_FRAM_PORT=7977
      ${builtins.readFile ./north-coord-runtime}
    '';
  };
in
{
  options.myConfig.modules.north-coord.enable = lib.mkEnableOption "Personal North coordinator daemon (:7977) — sole-writer fact-graph service for Tom's canonical log";
  # Socket activation is gated OFF until the fram daemon consumes the inherited
  # fd (M6 cutover cut). Activating it earlier makes systemd own :7977 while the
  # daemon still binds it itself -> bind conflict -> crash loop. The cutover
  # landing flips this default in the same commit that lands the fd consumer.
  options.myConfig.modules.north-coord.socketActivation = lib.mkEnableOption "systemd socket activation for :7977 (requires the fram fd-consumer from the M6 cutover cut)";
  config = lib.mkIf config.myConfig.modules.north-coord.enable {
    environment.systemPackages = [ northCoordRuntime ];
    systemd.sockets.north-coord = lib.mkIf config.myConfig.modules.north-coord.socketActivation {
      description = "North coordinator activation socket (:7977)";
      wantedBy = [ "sockets.target" ];
      listenStreams = [ "127.0.0.1:7977" ];
      socketConfig = {
        Backlog = 4096;
        FileDescriptorName = "north-coord";
      };
    };
    systemd.services.north-coord = {
      description = "North coordinator — personal fact-graph daemon (:7977)";
      wantedBy = [ "multi-user.target" ];
      requires = lib.mkIf config.myConfig.modules.north-coord.socketActivation [ "north-coord.socket" ];
      after = [ "network.target" ] ++ lib.optional config.myConfig.modules.north-coord.socketActivation "north-coord.socket";
      path = with pkgs; [ clojure jdk bash coreutils git ];
      startLimitIntervalSec = 0;
      restartIfChanged = true;
      environment = {
        HOME = homeDir;
        FRAM_REQUIRE_LOG_FENCE = "1";
        FRAM_TELEMETRY_LOG = "${homeDir}/.local/state/north/telemetry.log";
        JDK_JAVA_OPTIONS = "-Xmx6g";
      };
      serviceConfig = {
        Type = "simple";
        User = username;
        WorkingDirectory = homeDir;
        ExecStartPre = [
          "${northCoordRuntime}/bin/north-coord-runtime ensure-default"
          "${northCoordRuntime}/bin/north-coord-runtime prepare"
        ];
        # The sd-listen wrapper ships in north GIT MAIN but not yet in the
        # pinned nix package — wrapping unconditionally caused the 203/EXEC
        # crash loop of 2026-07-28. Gate it with socketActivation, whose flip
        # also requires a north flake-input bump that ships the wrapper.
        ExecStart =
          if config.myConfig.modules.north-coord.socketActivation
          then "${northPkg}/bin/north-coord-sd-listen ${northCoordRuntime}/bin/north-coord-runtime start"
          else "${northCoordRuntime}/bin/north-coord-runtime start";
        ExecStartPost = "${northCoordRuntime}/bin/north-coord-runtime settle";
        Restart = "always";
        RestartSec = 2;
        MemoryMax = "8G";
        MemorySwapMax = "0";
      };
    };
  };
}
