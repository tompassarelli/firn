{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.myConfig.modules.backup-vault;
  dir = "/var/lib/backup-vault";
  gib = n: toString (n * 1024 * 1024 * 1024);
  receive = pkgs.writeShellApplication {
    name = "backup-vault-receive";
    runtimeInputs = [
      pkgs.coreutils
    ];
    text = ''
      dir=${dir}
      quota=${gib cfg.quotaGiB}
      max_file=${gib cfg.maxFileGiB}
      ${builtins.readFile ./receive.sh}'';
  };
  entry =
    _: client:
    ''restrict,from="${client.address}",expiry-time="${client.expires}",command="${receive}/bin/backup-vault-receive" ${client.publicKey}'';
in
{
  options.myConfig.modules.backup-vault = {
    enable = lib.mkEnableOption "backup-vault: an ssh-only drop box where named clients can list and put new age-encrypted archives but never read, overwrite or delete one";
    clients = lib.mkOption {
      default = { };
      description = "clients keyed by name";
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            publicKey = lib.mkOption {
              type = lib.types.strMatching "ssh-ed25519 [A-Za-z0-9+/=]+( [A-Za-z0-9._@-]+)?";
              description = "public half of the client's key; the private half stays in the private overlay's sops file";
            };
            address = lib.mkOption {
              type = lib.types.strMatching "[0-9.]+";
              description = "the only source address sshd accepts this key from";
            };
            expires = lib.mkOption {
              type = lib.types.strMatching "[0-9]{8}";
              description = "YYYYMMDD after which sshd refuses the key";
            };
          };
        }
      );
    };
    quotaGiB = lib.mkOption {
      type = lib.types.ints.positive;
      default = 20;
      description = "the vault refuses new archives once it holds this much";
    };
    maxFileGiB = lib.mkOption {
      type = lib.types.ints.positive;
      default = 8;
      description = "largest single archive accepted";
    };
    keepDays = lib.mkOption {
      type = lib.types.ints.positive;
      default = 15;
      description = "archives older than this are pruned by the vault's own timer, which no client can trigger";
    };
  };
  config = lib.mkIf cfg.enable {
    users = {
      groups.vault = { };
      users.vault = {
        isSystemUser = true;
        group = "vault";
        home = dir;
        shell = "${pkgs.bash}/bin/bash";
        openssh.authorizedKeys.keys = lib.mapAttrsToList entry cfg.clients;
      };
    };
    services.openssh.settings.AllowUsers = [ "vault" ];
    systemd = {
      tmpfiles.rules = [ "d ${dir} 0700 vault vault -" ];
      services.backup-vault-prune = {
        description = "Prune backup-vault archives past their retention";
        serviceConfig = {
          Type = "oneshot";
          User = "vault";
          ExecStart = "${pkgs.findutils}/bin/find ${dir} -maxdepth 1 -type f -name '*.age' -mtime +${toString cfg.keepDays} -delete";
        };
      };
      timers.backup-vault-prune = {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = "daily";
          Persistent = true;
        };
      };
    };
  };
}
