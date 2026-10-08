{ config, lib, pkgs, ... }:
{ "config" = (lib."mkIf" (config."myConfig"."modules"."duf"."enable") ({ "environment" = { "systemPackages" = [ (pkgs."duf") ]; }; })); "options" = { "myConfig" = { "modules" = { "duf" = { "enable" = (lib."mkEnableOption" ("duf disk usage viewer")); }; }; }; }; }
