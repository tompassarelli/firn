{
  inputs = {
    nixpkgs = {
      url = "github:nixos/nixpkgs/nixos-26.05";
    };
    alpha = {
      url = "github:alpha/project";
    };
    zeta = {
      inputs.nixpkgs.follows = "nixpkgs";
      url = "github:zeta/project";
    };
  };
  outputs =
    {
      nixpkgs,
      alpha,
      zeta,
      ...
    }:
    {
      lib.mkSystem = nixpkgs.lib.nixosSystem {
        specialArgs = {
          inputs = {
            inherit alpha zeta;
          };
        };
      };
    };
}
