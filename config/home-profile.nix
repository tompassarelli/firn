{ config, lib, ... }:

{
  home.activation.installPackages = lib.mkForce (
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      firnTools="${config.home.homeDirectory}/.local/lib/firn/cli/current/bin/firn-tools"
      if [[ ! -e ${config.home.profileDirectory}/manifest.json ]]; then
        run nix-env -i ${config.home.path}
      elif ! run "$firnTools" profile replace home-manager-path ${config.home.path}; then
        nixProfileRemove home-manager-path
        run nix profile add ${config.home.path}
      fi
    ''
  );
}
