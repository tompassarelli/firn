{
  myConfig.modules.north-remote-serve = {
    enable = true;
    peers.gex45 = {
      publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFixtureFixtureFixtureFixtureFixtureFixtureFi gex45-bridge";
      address = "192.0.2.4";
      expires = "20270202";
      repos = [
        "north"
        "makgora"
      ];
    };
    southLand = {
      enable = true;
      command = "/run/current-system/sw/bin/south-land-fixture";
      mintCommand = "/run/current-system/sw/bin/mint-fixture";
    };
  };
}
