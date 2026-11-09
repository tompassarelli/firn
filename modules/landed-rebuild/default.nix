{
  config,
  lib,
  pkgs,
  flakeRoot,
  ...
}:

let
  username = config.myConfig.modules.users.username;
  homeDir = config.myConfig.modules.users.homeDir;
  cfg = config.myConfig.modules.landed-rebuild;
  system = cfg.systemFlake;
  private = system != null && system.sopsFile != null;
  credentials = [
    "app-id"
    "installation-id"
    "private-key"
  ];
  secret = name: "landed-rebuild-${name}";
  environmentSwitch = pkgs.writeShellScript "firn-environment-switch" (
    builtins.readFile "${flakeRoot}/dotfiles/bin/firn-environment-switch"
  );
  systemHeader = pkgs.writeShellApplication {
    name = "firn-landed-rebuild-system-header";
    runtimeInputs = [
      pkgs.gh-token
      pkgs.curl
      pkgs.jq
      pkgs.coreutils
    ];
    text = ''
      jwt=$(gh-token generate --jwt --duration 2 --app-id "$(cat "$CREDENTIALS_DIRECTORY/app-id")" --key "$CREDENTIALS_DIRECTORY/private-key")
      token=$(printf 'header = "Authorization: Bearer %s"\n' "$jwt" \
        | curl -fsS --max-time 30 --config - -X POST -H 'Accept: application/vnd.github+json' \
          -d ${
            lib.escapeShellArg (
              builtins.toJSON {
                repositories = [ (lib.removeSuffix ".git" (baseNameOf system.origin)) ];
                permissions.contents = "read";
              }
            )
          } \
          "https://api.github.com/app/installations/$(cat "$CREDENTIALS_DIRECTORY/installation-id")/access_tokens" \
        | jq -er .token)
      printf 'Authorization: Basic %s' "$(printf 'x-access-token:%s' "$token" | base64 -w0)"
    '';
  };
in
{
  options.myConfig.modules.landed-rebuild = {
    enable = lib.mkEnableOption "Activate only the freshly fetched landed main commit from sandboxed agents";
    systemFlake = lib.mkOption {
      type = lib.types.nullOr (
        lib.types.submodule {
          options = {
            origin = lib.mkOption {
              type = lib.types.str;
              example = "https://github.com/owner/overlay.git";
              description = "HTTPS URL of the system flake repository; each request fetches its main from here as root and builds it around the Firn snapshot.";
            };
            sopsFile = lib.mkOption {
              type = lib.types.nullOr lib.types.path;
              default = null;
              description = "sops file holding app_id, installation_id and private_key of a GitHub App installed on a private origin; the service loads them as systemd credentials and mints a one-hour contents-read token for that one repository per request.";
            };
          };
        }
      );
      default = null;
      description = "System flake that wraps Firn on this host; null builds Firn alone. No login user's checkout is read.";
    };
  };
  config = lib.mkIf cfg.enable {
    sops.secrets = lib.mkIf private (
      lib.genAttrs (map secret credentials) (name: {
        inherit (system) sopsFile;
        key = lib.replaceStrings [ "-" ] [ "_" ] (lib.removePrefix "landed-rebuild-" name);
      })
    );
    systemd = {
      sockets.firn-landed-rebuild = {
        description = "Firn landed-commit rebuild requests";
        wantedBy = [ "sockets.target" ];
        socketConfig = {
          ListenStream = "/run/firn-landed-rebuild.sock";
          SocketMode = "0600";
          SocketUser = username;
        };
      };
      services.firn-landed-rebuild = {
        description = "Activate the current Firn main commit through firn rebuild";
        path = [
          pkgs.git
          pkgs.util-linux
          pkgs.coreutils
        ];
        restartIfChanged = false;
        environment.PATH = lib.mkForce "/run/wrappers/bin:/run/current-system/sw/bin:${
          lib.makeBinPath [
            pkgs.git
            pkgs.util-linux
            pkgs.coreutils
          ]
        }";
        serviceConfig = {
          ExecStart = lib.concatStringsSep " " [
            "${pkgs.python3}/bin/python3"
            "${./landed-rebuild.py}"
            "serve"
            username
            homeDir
            "${pkgs.bun}/bin/bun"
            "${./runtime.mjs}"
            "${environmentSwitch}"
            (if system == null then "-" else system.origin)
            (if private then lib.getExe systemHeader else "${pkgs.coreutils}/bin/true")
          ];
          LoadCredential = lib.optionals private (
            map (name: "${name}:${config.sops.secrets.${secret name}.path}") credentials
          );
          StateDirectory = "firn-landed-rebuild";
          StateDirectoryMode = "0700";
          UMask = "0077";
          KillMode = "process";
          Restart = "on-failure";
        };
      };
    };
  };
}
