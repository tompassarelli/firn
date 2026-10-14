# Configuration queries

Use `firn schema explain <option>` for option declarations, `firn module
list all` for the module catalog and `firn tag resolve <host>` to explain
composition. Search actual Nix callers with `rg -n '<option>' modules hosts`.
Run `firn check` to evaluate option types and assertions before building.
