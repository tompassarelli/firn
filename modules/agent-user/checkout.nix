{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.myConfig.modules.agent-user;
  inherit (cfg) checkout;
  script = pkgs.writeShellScript "agent-north-checkout" ''
    export PATH=${
      lib.makeBinPath [
        pkgs.git
        pkgs.coreutils
        pkgs.bash
      ]
    }
    exec bash ${./checkout.sh} ${lib.escapeShellArg checkout.path} ${lib.escapeShellArg checkout.url}
  '';
in
{
  options.myConfig.modules.agent-user.checkout = {
    enable = lib.mkEnableOption "a checkout of the public north repository in the agent's home, cloned over https with no credential and fetched when present, so an agent session has a lane to run from";
    url = lib.mkOption {
      type = lib.types.strMatching "https://[^@ ]+";
      default = "https://github.com/tompassarelli/north.git";
      description = "Public https URL of the repository, carrying no userinfo";
    };
    path = lib.mkOption {
      type = lib.types.str;
      default = "${cfg.home}/code/north/main";
      defaultText = lib.literalExpression ''"''${config.myConfig.modules.agent-user.home}/code/north/main"'';
      description = "Directory of the checkout, under the agent's home";
    };
  };
  config = lib.mkIf (cfg.enable && checkout.enable) {
    assertions = [
      {
        assertion = lib.hasPrefix "${cfg.home}/" checkout.path;
        message = "the agent's north checkout must lie under ${cfg.home}";
      }
    ];
    systemd.tmpfiles.rules = [
      "d ${dirOf checkout.path} 0755 ${cfg.name} ${cfg.name} -"
      "d ${dirOf checkout.path}/worktrees 0755 ${cfg.name} ${cfg.name} -"
    ];
    systemd.services.agent-north-checkout = {
      description = "Clone or fetch the public north repository into the agent user's home, as the agent user, with no credential";
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ];
      after = [
        "network-online.target"
        "local-fs.target"
      ];
      environment.HOME = cfg.home;
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = cfg.name;
        Group = cfg.name;
        ExecStart = "-${script}";
        NoNewPrivileges = true;
        PrivateTmp = true;
      };
    };
  };
}
