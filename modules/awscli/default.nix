{ config, lib, pkgs, flakeRoot, ... }:

let
  username = config.myConfig.modules.users.username;
  sopsFile = config.myConfig.modules.awscli.sopsFile;
in
{
  options.myConfig.modules.awscli.enable = lib.mkEnableOption "awscli";
  options.myConfig.modules.awscli.sopsFile = lib.mkOption {
    type = lib.types.str;
    default = "${flakeRoot}/secrets/aws.yaml";
    description = "sops file holding the AWS credentials (aws-access-key-id, aws-secret-access-key)";
  };
  config = lib.mkIf config.myConfig.modules.awscli.enable {
    environment.systemPackages = [ pkgs.awscli2 ];
    sops.secrets = {
      "aws-access-key-id" = {
        sopsFile = sopsFile;
        owner = username;
      };
      "aws-secret-access-key" = {
        sopsFile = sopsFile;
        owner = username;
      };
    };
    sops.templates = {
      "aws-credentials" = {
        content = ''
          [default]
          aws_access_key_id = ${config.sops.placeholder.aws-access-key-id}
          aws_secret_access_key = ${config.sops.placeholder.aws-secret-access-key}

        '';
        owner = username;
      };
      "aws-config" = {
        content = ''
          [default]
          region = us-east-2
          output = json

        '';
        owner = username;
      };
    };
  };
}
