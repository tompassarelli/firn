{ config, lib, ... }:
{ "config" = (lib."mkIf" (config."myConfig"."modules"."ssh"."enable") ({ "services" = { "openssh" = { "enable" = true; "settings" = { "KbdInteractiveAuthentication" = false; "PasswordAuthentication" = false; }; }; }; })); "options" = { "myConfig" = { "modules" = { "ssh" = { "enable" = (lib."mkEnableOption" ("SSH server")); }; }; }; }; }
