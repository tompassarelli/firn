{ config, lib, pkgs, ... }:
{ "config" = (lib."mkIf" (config."myConfig"."modules"."hyperfine"."enable") ({ "environment" = { "systemPackages" = [ (pkgs."hyperfine") ]; }; })); "options" = { "myConfig" = { "modules" = { "hyperfine" = { "enable" = (lib."mkEnableOption" ("hyperfine command benchmarking")); }; }; }; }; }
