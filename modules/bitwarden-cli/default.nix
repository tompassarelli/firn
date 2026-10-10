{ config, lib, pkgs, ... }:
{ "config" = (lib."mkIf" (config."myConfig"."modules"."bitwarden-cli"."enable") ({ "environment" = { "systemPackages" = [ (pkgs."bitwarden-cli") ]; }; })); "options" = { "myConfig" = { "modules" = { "bitwarden-cli" = { "enable" = (lib."mkEnableOption" ("bw — Bitwarden vault CLI")); }; }; }; }; }
