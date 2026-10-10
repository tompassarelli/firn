{ config, lib, pkgs, ... }:
{ "config" = (lib."mkIf" (config."myConfig"."modules"."bun"."enable") ({ "environment" = { "systemPackages" = [ (pkgs."bun") ]; }; })); "options" = { "myConfig" = { "modules" = { "bun" = { "enable" = (lib."mkEnableOption" ("Bun JavaScript runtime and package manager")); }; }; }; }; }
