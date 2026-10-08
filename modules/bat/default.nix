{ config, lib, pkgs, ... }:
{ "config" = (lib."mkIf" (config."myConfig"."modules"."bat"."enable") ({ "environment" = { "systemPackages" = [ (pkgs."bat") ]; }; })); "options" = { "myConfig" = { "modules" = { "bat" = { "enable" = (lib."mkEnableOption" ("bat syntax-highlighting cat")); }; }; }; }; }
