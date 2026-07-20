{ config, lib, pkgs, inputs, flakeRoot, ... }:

let
  username = config.myConfig.modules.users.username;
  minimalPkg = inputs.hermes-agent.packages."${pkgs.stdenv.hostPlatform.system}".minimal;
  hermesPkg = minimalPkg.override (prev: {
    callPackage = f: args: let
      drv = prev.callPackage f args;
    in
    if ((drv.pname or null) == "hermes-tui") then drv.overrideAttrs (o: {
      src = inputs.hermes-agent;
    }) else drv;
  });
  northPkg = inputs.north.packages."${pkgs.stdenv.hostPlatform.system}".default;
  northBin = "${northPkg}/bin";
in
{
  options.myConfig.modules.hermes.enable = lib.mkEnableOption "Hermes controller host over the North MCP with the fail-closed north-bridge adapter";
  config = lib.mkIf config.myConfig.modules.hermes.enable {
    environment.systemPackages = [ hermesPkg ];
    environment.variables.NORTH_HERMES_LIFECYCLE_DIR = northBin;
    home-manager.users.${username} = ({ config, ... }: {
      home.sessionVariables.NORTH_HERMES_LIFECYCLE_DIR = northBin;
      home.file = {
        ".hermes/config.yaml".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/code/nixos-config/dotfiles/hermes/config.yaml";
        ".hermes/SOUL.md".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/code/nixos-config/dotfiles/agents/AGENTS.md";
        ".hermes/plugins/north-bridge".source = "${flakeRoot}/dotfiles/hermes/plugins/north-bridge";
      };
    });
  };
}
