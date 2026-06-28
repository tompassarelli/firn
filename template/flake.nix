{
  description = "My NixOS configuration powered by firn";

  inputs = {
    # firn - the module framework
    firn.url = "github:tompassarelli/firn";

    # You can add your own inputs here
    # my-package.url = "github:someone/something";
  };

  outputs = { self, firn, ... }@inputs: {
    nixosConfigurations = {
      # Your machine - rename "my-machine" to your hostname
      my-machine = firn.lib.mkSystem {
        hostname = "my-machine";
        hostConfig = ./hosts/my-machine/configuration.nix;
        hardwareConfig = ./hosts/my-machine/hardware-configuration.nix;

        # Optional: Add your own modules
        # extraModules = [ ./modules/my-custom-module ];

        # Optional: Add your own overlays
        # extraOverlays = [
        #   (final: prev: {
        #     my-package = inputs.my-package.packages.${final.system}.default;
        #   })
        # ];

        # Optional: Pass extra args to modules
        # extraSpecialArgs = { inherit inputs; };
      };

      # Add more machines here
      # another-machine = firn.lib.mkSystem { ... };
    };
  };
}
