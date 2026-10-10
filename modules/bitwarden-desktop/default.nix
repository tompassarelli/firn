{ config, lib, pkgs, ... }:
{ "config" = (lib."mkIf" (config."myConfig"."modules"."bitwarden-desktop"."enable") ({ "environment" = { "systemPackages" = [ (pkgs."bitwarden-desktop") ]; }; })); "options" = { "myConfig" = { "modules" = { "bitwarden-desktop" = { "enable" = (lib."mkEnableOption" ("Bitwarden desktop app")); }; }; }; }; }
