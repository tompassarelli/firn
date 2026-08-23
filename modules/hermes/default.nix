{ config, lib, pkgs, inputs, flakeRoot, ... }:

((username: ((homeDir: ((minimalPkg: ((hermesPkg: ((northPkg: ((northBin: {
  flake-inputs = {
    hermes-agent = {
      url = "github:NousResearch/hermes-agent/244dabbd9c4b542bf5c1ad0159af512c2b5d6e08";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
  options.myConfig.modules.hermes.enable = lib.mkEnableOption "Hermes controller host over the North MCP with the fail-closed north-bridge adapter";
  config = lib.mkIf config.myConfig.modules.hermes.enable {
    environment.systemPackages = [ hermesPkg ];
    environment.variables.NORTH_HERMES_LIFECYCLE_DIR = northBin;
    home-manager.users.${username} = ({ config, ... }: {
      home.sessionVariables.NORTH_HERMES_LIFECYCLE_DIR = northBin;
      home.file = {
        ".hermes/config.yaml".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/code/nixos-config/dotfiles/hermes/config.yaml";
        ".hermes/SOUL.md".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.config/agents/AGENTS.md";
        ".hermes/plugins/north-bridge".source = "${flakeRoot}/dotfiles/hermes/plugins/north-bridge";
      };
    });
  };
}) "${northPkg}/bin")) "${homeDir}/code/north/main")) (minimalPkg.override (prev: {
    callPackage = f: args: ((drv: if ((drv.pname or null) == "hermes-tui") then drv.overrideAttrs (o: {
      src = inputs.hermes-agent;
    }) else drv) (prev.callPackage f args));
  })))) (inputs.hermes-agent.packages."${pkgs.stdenv.hostPlatform.system}").minimal)) config.myConfig.modules.users.homeDir)) config.myConfig.modules.users.username)
