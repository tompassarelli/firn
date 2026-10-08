{ config, lib, pkgs, ... }:
{ "config" = (lib."mkIf" (config."myConfig"."modules"."ast-grep"."enable") ({ "environment" = { "systemPackages" = [ (pkgs."ast-grep") ]; }; })); "options" = { "myConfig" = { "modules" = { "ast-grep" = { "enable" = (lib."mkEnableOption" ("ast-grep structural code search")); }; }; }; }; }
