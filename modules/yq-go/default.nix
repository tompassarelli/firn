{ config, lib, pkgs, ... }:
{ "config" = (lib."mkIf" (config."myConfig"."modules"."yq-go"."enable") ({ "environment" = { "systemPackages" = [ (pkgs."yq-go") ]; }; })); "options" = { "myConfig" = { "modules" = { "yq-go" = { "enable" = (lib."mkEnableOption" ("yq YAML/JSON/TOML processor")); }; }; }; }; }
