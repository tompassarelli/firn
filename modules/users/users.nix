{ config, lib, pkgs, ... }:

let
  username = config.myConfig.modules.users.username;
  homeDir = config.myConfig.modules.users.homeDir;
in
{
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
  config = lib.mkIf config.myConfig.modules.users.enable {
    users.users.${username} = {
      shell = pkgs.bashInteractive;
      isNormalUser = true;
      home = homeDir;
      extraGroups = [ "wheel" "networkmanager" "plugdev" ];
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
