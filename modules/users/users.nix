{ config, lib, pkgs, ... }:

((username: ((homeDir: {
  options.myConfig.modules.users.enable = lib.mkEnableOption "Enable user configuration";
  options.myConfig.modules.users.username = lib.mkOption {
    type = lib.types.str;
    default = "user";
    description = "Primary system username (instance binds the real one)";
  };
  options.myConfig.modules.users.email = lib.mkOption {
    type = lib.types.str;
    default = "";
    description = "Primary git/commit email";
  };
  options.myConfig.modules.users.fullName = lib.mkOption {
    type = lib.types.str;
    default = "";
    description = "Git author / display name (git user.name)";
  };
  options.myConfig.modules.users.homeDir = lib.mkOption {
    type = lib.types.str;
    default = "/home/${username}";
    description = "User home directory";
  };
  options.myConfig.modules.users.codeDir = lib.mkOption {
    type = lib.types.str;
    default = "${homeDir}/code";
    description = "Root of source checkouts (the ~/code convention)";
  };
  options.myConfig.modules.users.mutable = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = "Allow imperative user changes (users.mutableUsers)";
  };
  options.myConfig.modules.users.authorizedKeys = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [ ];
    description = "SSH public keys allowed to log in as the primary user";
  };
  options.myConfig.modules.users.extraGroups = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [ "wheel" "networkmanager" "plugdev" ];
    description = "Supplementary groups of the primary user";
  };
  options.myConfig.modules.users.passwordHashSopsFile = lib.mkOption {
    type = lib.types.nullOr lib.types.path;
    default = null;
    description = "sops file whose `password_hash` key holds the primary user's password hash";
  };
  config = lib.mkIf config.myConfig.modules.users.enable {
    users.mutableUsers = config.myConfig.modules.users.mutable;
    users.users.${username} = {
      shell = pkgs.bashInteractive;
      isNormalUser = true;
      home = homeDir;
      extraGroups = config.myConfig.modules.users.extraGroups;
      openssh.authorizedKeys.keys = config.myConfig.modules.users.authorizedKeys;
      hashedPasswordFile = lib.mkIf (config.myConfig.modules.users.passwordHashSopsFile != null) config.sops.secrets.user-password-hash.path;
    };
    sops.secrets = lib.mkIf (config.myConfig.modules.users.passwordHashSopsFile != null) {
      "user-password-hash" = {
        sopsFile = config.myConfig.modules.users.passwordHashSopsFile;
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
}) config.myConfig.modules.users.homeDir)) config.myConfig.modules.users.username)
