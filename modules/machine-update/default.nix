{
  config,
  lib,
  pkgs,
  jobRun,
  northBin,
  ...
}:

let
  cfg = config.myConfig.modules.machine-update;
  homeDir = config.myConfig.modules.users.homeDir;
  username = config.myConfig.modules.users.username;
  run = jobName: mode: jobRun jobName "${homeDir}/.local/share/firn/bin/machine-update ${mode}";
  pushHost = repo: "${lib.replaceStrings [ "/" ] [ "." ] repo}.deploy.github.com";
  pushKeys = lib.mapAttrsToList (repo: key: { inherit repo key; }) cfg.pushKeys;
  githubHostKeys = pkgs.writeText "machine-update-github-known-hosts" ''
    github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl
  '';
  pushSshConfig = pkgs.writeText "machine-update-ssh-config" (
    lib.concatMapStrings (push: ''
      Host ${pushHost push.repo}
        HostName github.com
        User git
        IdentityFile ${push.key}
        IdentitiesOnly yes
    '') pushKeys
    + ''
      Host *
        BatchMode yes
        StrictHostKeyChecking yes
        HostKeyAlgorithms ssh-ed25519
        UserKnownHostsFile ${githubHostKeys}
        GlobalKnownHostsFile /dev/null
    ''
  );
  pushEnvironment = lib.optionals (pushKeys != [ ]) (
    [
      "\"GIT_SSH_COMMAND=${pkgs.openssh}/bin/ssh -F ${pushSshConfig}\""
      "GIT_CONFIG_COUNT=${toString (lib.length pushKeys)}"
    ]
    ++ lib.concatLists (
      lib.imap0 (i: push: [
        "GIT_CONFIG_KEY_${toString i}=url.git@${pushHost push.repo}:${push.repo}.pushInsteadOf"
        "GIT_CONFIG_VALUE_${toString i}=https://github.com/${push.repo}"
      ]) pushKeys
    )
  );
in
{
  options.myConfig.modules.machine-update = {
    enable = lib.mkEnableOption "Nightly machine software update";
    writer = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Land nightly security inputs; other hosts only apply the landed inputs";
    };
    apply = lib.mkOption {
      type = lib.types.bool;
      default = !cfg.writer;
      defaultText = lib.literalExpression "!writer";
      description = "Rebuild this host from the landed inputs, after landing them when it is also the writer";
    };
    pushKeys = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      example = {
        "tompassarelli/firn" = "/home/tom/.local/state/machine-updates/deploy-keys/firn";
      };
      description = "SSH deploy key file per GitHub repository (owner/name) the writer pushes to, instead of the host's HTTPS credential";
    };
  };
  config = lib.mkIf cfg.enable {
    home-manager.users.${username} = _: {
      systemd.user = {
        services.machine-update = {
          Unit = {
            Description = "Nightly machine software update";
            OnFailure = [
              (if cfg.apply then "update-notify@%n.service" else "nexus-notify@%n.service")
            ];
            X-SwitchMethod = "keep-old";
          };
          Service = {
            Type = "oneshot";
            TimeoutStartSec = "4h";
            Environment = [
              "PATH=/run/wrappers/bin:/run/current-system/sw/bin:${homeDir}/.local/share/firn/bin:${northBin}:${
                lib.makeBinPath [
                  pkgs.bash
                  pkgs.bun
                  pkgs.coreutils
                  pkgs.curl
                  pkgs.git
                  pkgs.gh
                  pkgs.jq
                  pkgs.nix
                  pkgs.python3
                  pkgs.zstd
                  pkgs.util-linux
                  pkgs.libnotify
                  pkgs.systemd
                ]
              }"
            ]
            ++ pushEnvironment;
            ExecStart =
              lib.optional cfg.writer (run "machine-update" "--write")
              ++ lib.optional cfg.apply (run "machine-update" "--apply");
          };
        };
        timers.machine-update = {
          Unit.Description = "Nightly machine software update";
          Timer = {
            OnCalendar = "02:00";
            Persistent = true;
            RandomizedDelaySec = "5m";
          };
          Install.WantedBy = [ "timers.target" ];
        };
      };
    };
  };
}
