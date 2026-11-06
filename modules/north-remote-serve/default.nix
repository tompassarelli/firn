{
  config,
  lib,
  northBin,
  ...
}:

let
  cfg = config.myConfig.modules.north-remote-serve;
  username = config.myConfig.modules.users.username;
  homeDir = config.myConfig.modules.users.homeDir;
  tokenDir = "/run/south-land-token";
  entry =
    name: peer:
    ''restrict,from="${peer.address}",expiry-time="${peer.expires}",command="${northBin}/north remote-serve --peer ${name}${
      lib.optionalString (peer.repos != [ ]) " --repos ${lib.concatStringsSep "," peer.repos}"
    }" ${peer.publicKey}'';
in
{
  options.myConfig.modules.north-remote-serve = {
    enable = lib.mkEnableOption "the north remote-serve dispatcher as the only ssh entry for named peers, with sshd reading no home-directory authorized_keys";
    peers = lib.mkOption {
      default = { };
      description = "peers that reach this host only through north remote-serve, keyed by peer name";
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            publicKey = lib.mkOption {
              type = lib.types.strMatching "ssh-ed25519 [A-Za-z0-9+/=]+( [A-Za-z0-9._@-]+)?";
              description = "public half of the peer's key; the private half stays in the private overlay's sops file";
            };
            address = lib.mkOption {
              type = lib.types.strMatching "[0-9.]+";
              description = "the only source address sshd accepts this key from";
            };
            expires = lib.mkOption {
              type = lib.types.strMatching "[0-9]{8}";
              description = "YYYYMMDD after which sshd refuses the key";
            };
            repos = lib.mkOption {
              type = lib.types.listOf (lib.types.strMatching "[a-z0-9-]+");
              default = [ ];
              description = "repositories whose items the peer may name in threads calls; none refuses every item ref";
            };
          };
        }
      );
    };
    southLand = {
      enable = lib.mkEnableOption "the south-land socket and its sandboxed per-connection handler";
      command = lib.mkOption {
        type = lib.types.str;
        description = "handler command run per connection with the patch on stdin; it must live outside /home and read its token from $CREDENTIALS_DIRECTORY/github-token";
      };
      mintCommand = lib.mkOption {
        type = lib.types.str;
        description = "root command that prints a south-only contents:write GitHub token on stdout";
      };
    };
  };
  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        services.openssh.authorizedKeysInHomedir = false;
        users.users.${username}.openssh.authorizedKeys.keys = lib.mapAttrsToList entry cfg.peers;
      }
      (lib.mkIf cfg.southLand.enable {
        systemd = {
          sockets.south-land = {
            description = "south land requests from north remote-serve";
            wantedBy = [ "sockets.target" ];
            socketConfig = {
              ListenStream = "/run/south-land/south-land.sock";
              Accept = true;
              SocketUser = username;
              SocketMode = "0600";
              DirectoryMode = "0755";
            };
          };
          services."south-land-token" = {
            description = "Mint a one-hour south-only token for one south land";
            serviceConfig = {
              Type = "oneshot";
              RuntimeDirectory = "south-land-token";
              RuntimeDirectoryMode = "0700";
              RuntimeDirectoryPreserve = true;
              UMask = "0077";
            };
            script = ''
              ${cfg.southLand.mintCommand} >${tokenDir}/token.new
              mv ${tokenDir}/token.new ${tokenDir}/token
            '';
          };
          services."south-land@" = {
            description = "Land one prose-only south patch from a remote-serve peer";
            requires = [ "south-land-token.service" ];
            after = [ "south-land-token.service" ];
            serviceConfig = {
              ExecStart = cfg.southLand.command;
              ExecStopPost = "+/run/current-system/sw/bin/rm -f ${tokenDir}/token";
              StandardInput = "socket";
              StandardOutput = "socket";
              StandardError = "journal";
              DynamicUser = true;
              StateDirectory = "south-land";
              LoadCredential = "github-token:${tokenDir}/token";
              InaccessiblePaths = [
                homeDir
                "/run/secrets"
              ];
              ProtectSystem = "strict";
              ProtectHome = true;
              PrivateTmp = true;
              NoNewPrivileges = true;
              RuntimeMaxSec = 600;
            };
          };
        };
      })
    ]
  );
}
