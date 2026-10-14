{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myConfig.modules.awscli;
in
{
  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ pkgs.awscli2 ];
    sops = {
      secrets = {
        aws-access-key-id = {
          owner = config.myConfig.modules.users.username;
          sopsFile = config.myConfig.modules.awscli.sopsFile;
        };
        aws-secret-access-key = {
          owner = config.myConfig.modules.users.username;
          sopsFile = config.myConfig.modules.awscli.sopsFile;
        };
      };
      templates = {
        aws-config = {
          content = ''
            [default]
            region = us-east-2
            output = json

          '';
          owner = config.myConfig.modules.users.username;
        };
        aws-credentials = {
          content = ''
            [default]
            aws_access_key_id = ${config.sops.placeholder.aws-access-key-id}
            aws_secret_access_key = ${config.sops.placeholder.aws-secret-access-key}

          '';
          owner = config.myConfig.modules.users.username;
        };
      };
    };
  };
  options.myConfig.modules.awscli = {
    enable = lib.mkEnableOption "awscli";
    sopsFile = lib.mkOption {
      type = lib.types.str;
      description = "sops file holding the AWS credentials (aws-access-key-id, aws-secret-access-key)";
    };
  };
}
