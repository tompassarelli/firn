{ config, lib, pkgs, ... }:
{ "config" = (lib."mkIf" (config."myConfig"."modules"."sd"."enable") ({ "environment" = { "systemPackages" = [ (pkgs."sd") ]; }; })); "options" = { "myConfig" = { "modules" = { "sd" = { "enable" = (lib."mkEnableOption" ("sd find-and-replace tool")); }; }; }; }; }
