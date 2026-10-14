# Diagnosing option errors

Run `firn check` to get the NixOS evaluation error and source location.
Inspect the declared option with `firn schema explain services.openssh.enable`
and check callers with `rg -n 'services.openssh' modules hosts`.

Option declarations determine the accepted type. Unknown paths must be
corrected in the source; failed assertions name the requirement to satisfy.
If a private overlay provides the failing value, check that overlay's flake.
