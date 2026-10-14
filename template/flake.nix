{
  description = "My NixOS configuration powered by firn";
  inputs.firn.url = "github:tompassarelli/firn";
  outputs = { firn, ... }: {
    nixosConfigurations.my-machine = firn.lib.mkSystem {
      hostname = "my-machine";
      hostConfig = ./hosts/my-machine/configuration.nix;
      hardwareConfig = ./hosts/my-machine/hardware-configuration.nix;
    };
  };
}
