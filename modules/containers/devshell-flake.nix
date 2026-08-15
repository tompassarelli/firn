{
  description = "Dev sandbox environment";
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  };
  outputs = ({ nixpkgs, ... }: ((system: ((pkgs: {
    devShells = {
      ${system} = {
        default = pkgs.mkShell {
          packages = [ ];
        };
      };
    };
  }) (builtins.getAttr system nixpkgs.legacyPackages))) "x86_64-linux"));
}
