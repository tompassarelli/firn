{ config, lib, pkgs, ... }:

((cfg: ((username: ((passwordFile: ((start: {
  options.myConfig.modules.keyring-headless.enable = lib.mkEnableOption "headless GNOME Keyring Secret Service for a lingering user, unlocked from sops";
  options.myConfig.modules.keyring-headless.sopsFile = lib.mkOption {
    type = lib.types.path;
    description = "sops file whose keyring-password key unlocks the login keyring";
  };
  config = lib.mkIf cfg.enable {
    sops.secrets.keyring-password = {
      sopsFile = cfg.sopsFile;
      owner = username;
      mode = "0400";
    };
    users.users.${username}.linger = true;
    environment.systemPackages = [ pkgs.gnome-keyring pkgs.libsecret ];
    home-manager.users.${username} = ({ config, ... }: {
      systemd.user.services.gnome-keyring = {
        Unit = {
          Description = "GNOME Keyring Secret Service, unlocked from sops";
        };
        Service = {
          Type = "dbus";
          BusName = "org.freedesktop.secrets";
          ExecStart = "${start}/bin/keyring-headless-start";
          Restart = "on-failure";
        };
        Install = {
          WantedBy = [ "default.target" ];
        };
      };
    });
  };
}) (pkgs.writeShellApplication {
    name = "keyring-headless-start";
    runtimeInputs = [ pkgs.gnome-keyring pkgs.coreutils ];
    text = ''
      password=$(cat ${passwordFile})
      exec gnome-keyring-daemon --foreground --unlock --components=secrets < <(printf %s "$password")
    '';
  }))) config.sops.secrets.keyring-password.path)) config.myConfig.modules.users.username)) config.myConfig.modules.keyring-headless)
