{
  myConfig.modules.github-pat = {
    enable = false;
    nixAccessTokenFile = "/run/secrets/nix-access-tokens";
    applyTokenFile = "/run/nexus-gh-token/apply";
    workTokenFile = "/run/nexus-gh-token/work";
  };
}
