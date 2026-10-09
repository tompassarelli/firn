{ config, lib, pkgs, ... }:
{ "config" = (lib."mkIf" (config."myConfig"."modules"."sox"."enable") ({ "environment" = { "systemPackages" = [ (pkgs."sox") ]; }; })); "options" = { "myConfig" = { "modules" = { "sox" = { "enable" = (lib."mkEnableOption" ("Enable SoX audio recording for Claude Code voice mode")); }; }; }; }; }
