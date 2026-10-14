{
  description = "Dev sandbox environment";
  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  outputs =
    { nixpkgs, ... }:
    let
      system = "x86_64-linux";
      pkgs = builtins.getAttr system nixpkgs.legacyPackages;
    in
    {
      devShells.${system}.default = pkgs.mkShell { packages = [ ]; };
    };
}
