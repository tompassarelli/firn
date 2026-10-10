{ config, lib, pkgs, ... }:
{ "config" = (lib."mkIf" (config."myConfig"."modules"."gemini-cli"."enable") ({ "environment" = { "systemPackages" = [ (pkgs."gemini-cli") ]; }; })); "options" = { "myConfig" = { "modules" = { "gemini-cli" = { "enable" = (lib."mkEnableOption" ("Gemini CLI for free-tier adversarial review")); }; }; }; }; }
