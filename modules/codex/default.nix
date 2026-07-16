{ config, lib, pkgs, ... }:

let
  username = config.myConfig.modules.users.username;
in
{
  options.myConfig.modules.codex.enable = lib.mkEnableOption "OpenAI Codex CLI (master/bleeding-edge)";
  config = lib.mkIf config.myConfig.modules.codex.enable {
    environment.systemPackages = [ pkgs.master.codex ];
    home-manager.users.${username} = ({ config, ... }: {
      home.file = {
        ".codex/AGENTS.md".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/code/nixos-config/dotfiles/agents/AGENTS.md";
        ".codex/config.toml".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/code/nixos-config/dotfiles/codex/config.toml";
        ".codex/hooks.json".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/code/nixos-config/dotfiles/codex/hooks.json";
      };
    });
  };
}
