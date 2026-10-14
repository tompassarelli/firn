# Flake inputs

`flake.nix` owns the input URLs, follows relationships and values passed to
modules through `specialArgs`. Modules record required inputs in their
`metadata.json` `flakeInputs` field. Keep those declarations consistent when
adding or removing an input.

```bash
firn flake-input resolve emit
firn check
```

Two modules must not require the same input name with different URLs.
Input changes also require inspecting and committing the lock change.
Advance existing inputs only when the requested task includes upgrading.
