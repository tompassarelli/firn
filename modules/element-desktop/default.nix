{ config, lib, pkgs, ... }:
{ "config" = (lib."mkIf" (config."myConfig"."modules"."element-desktop"."enable") ({ "environment" = { "systemPackages" = [ (pkgs."element-desktop") ]; }; })); "options" = { "myConfig" = { "modules" = { "element-desktop" = { "enable" = (lib."mkEnableOption" ("Element Matrix desktop client")); }; }; }; }; }
