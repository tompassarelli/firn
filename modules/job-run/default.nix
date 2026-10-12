{ config, lib, pkgs, ... }:

let
  homeDir = config.myConfig.modules.users.homeDir;
  username = config.myConfig.modules.users.username;
  recordPath = lib.makeBinPath [ pkgs.python3 pkgs.openssh pkgs.coreutils pkgs.util-linux pkgs.hostname ];
in {
  _module.args.jobRun = name: cmd: "${pkgs.bash}/bin/bash ${homeDir}/.local/share/north/bin/job-run --path ${recordPath} --user ${username} ${name} -- ${cmd}";
}
