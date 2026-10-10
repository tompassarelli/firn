{ config, lib, pkgs, ... }:

((homeDir: ((username: ((recordPath: {
  _module.args.jobRun = name: cmd: "${pkgs.bash}/bin/bash ${homeDir}/.local/share/north/bin/job-run --path ${recordPath} --user ${username} ${name} -- ${cmd}";
}) (lib.makeBinPath [ pkgs.python3 pkgs.openssh pkgs.coreutils pkgs.util-linux pkgs.hostname ]))) config.myConfig.modules.users.username)) config.myConfig.modules.users.homeDir)
