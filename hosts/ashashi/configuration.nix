{ config, lib, pkgs, ... }:

{
  myConfig.modules.users.username = "ashashi";
  myConfig.modules.users.email = "tom.passarelli@protonmail.com";
  myConfig.modules.users.fullName = "tompassarelli";
  imports = [ ./_generated-enables.nix ];
}
