{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.myConfig.modules.users;
  inherit (cfg) username homeDir;
in
{
  options.myConfig.modules.users = {
    enable = lib.mkEnableOption "Enable user configuration";
    username = lib.mkOption {
      type = lib.types.str;
      default = "user";
      description = "Primary system username (instance binds the real one)";
    };
    email = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "Primary git/commit email";
    };
    fullName = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "Git author / display name (git user.name)";
    };
    homeDir = lib.mkOption {
      type = lib.types.str;
      default = "/home/${username}";
      description = "User home directory";
    };
    codeDir = lib.mkOption {
      type = lib.types.str;
      default = "${homeDir}/code";
      description = "Root of source checkouts (the ~/code convention)";
    };
    mutable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Allow imperative user changes (users.mutableUsers)";
    };
    authorizedKeys = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "SSH public keys allowed to log in as the primary user";
    };
    extraGroups = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "wheel"
        "networkmanager"
        "plugdev"
      ];
      description = "Supplementary groups of the primary user";
    };
    passwordHashSopsFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "sops file whose `password_hash` key holds the primary user's password hash";
    };
  };
  config = lib.mkIf cfg.enable {
    users = {
      mutableUsers = cfg.mutable;
      users.${username} = {
        shell = pkgs.bashInteractive;
        isNormalUser = true;
        home = homeDir;
        inherit (cfg) extraGroups;
        openssh.authorizedKeys.keys = cfg.authorizedKeys;
        hashedPasswordFile = lib.mkIf (
          cfg.passwordHashSopsFile != null
        ) config.sops.secrets.user-password-hash.path;
      };
    };
    sops.secrets = lib.mkIf (cfg.passwordHashSopsFile != null) {
      user-password-hash = {
        sopsFile = cfg.passwordHashSopsFile;
        key = "password_hash";
        neededForUsers = true;
      };
    };
    security.sudo.extraConfig = ''
      Defaults timestamp_timeout=30
      Defaults timestamp_type=global

    '';
    systemd.tmpfiles.rules = [
      "d ${homeDir}/Documents 0755 ${username} users -"
      "d ${homeDir}/Pictures/Screenshots 0755 ${username} users -"
      "d ${homeDir}/code 0755 ${username} users -"
      "d ${homeDir}/src 0755 ${username} users -"
    ];
  };
}
